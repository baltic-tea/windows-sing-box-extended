#requires -version 5.1

[CmdletBinding()]
param(
    [ValidateSet("Install", "Update", "Uninstall", "Run", "ServiceInstall", "ServiceRemove")]
    [string]$Action = "Install",

    [string]$DestFile = "",

    # Used by -Action Run, -Action ServiceInstall, -CreateService, and -ImportConfig target.
    [string]$ConfigFile = "",

    # podkop if exists, otherwise sing-box-extended if exists, otherwise sing-box if exists, otherwise sing-box-extended.
    [string]$ServiceName = "",

    # Create/recreate a Windows Service after installing the binary.
    [switch]$CreateService,

    # Explicit actions/flow.
    [switch]$RunNow,
    [switch]$RunAfterInstallPrompt,
    [switch]$NoRunPrompt,
    [switch]$ForceReinstall,

    # Copy existing config to install directory as config.json unless -ConfigFile is specified.
    [string]$ImportConfig = "",

    # Use -AddToMachinePath to add destination directory to Machine PATH instead.
    # Use -NoAddToPath to disable PATH modification.
    [Alias("NoAddToUserPath")]
    [switch]$NoAddToPath,

    [switch]$AddToMachinePath,

    # Force Windows asset architecture.
    [ValidateSet("", "amd64", "arm64", "386")]
    [string]$ArchSuffix = "",

    # Disable ANSI colors.
    [switch]$NoColor
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ApiUrl = "https://api.github.com/repos/shtorm-7/sing-box-extended/releases?per_page=30"
$ReleaseApiBase = "https://api.github.com/repos/shtorm-7/sing-box-extended/releases/tags"
$ArchiveName = "sing-box-latest.zip"

$Esc = [char]27
if ($NoColor) {
    $R = ""
    $G = ""
    $Y = ""
    $C = ""
    $N = ""
} else {
    $R = "$Esc[1;31m"
    $G = "$Esc[1;32m"
    $Y = "$Esc[1;33m"
    $C = "$Esc[1;36m"
    $N = "$Esc[0m"
}

$script:WorkDir = ""
$script:ServiceStopped = $false
$script:ResolvedServiceName = ""
$script:BackupPath = ""
$script:BackupOriginalPath = ""

function Write-RawLine {
    param([string]$Text)
    [Console]::WriteLine($Text)
}

function Write-Raw {
    param([string]$Text)
    [Console]::Write($Text)
}

function Test-Yes {
    param([string]$Value)
    return ([string]$Value).Trim() -match "(?i)^(y|yes)$"
}

function Restart-StoppedService {
    if ($script:ServiceStopped -and -not [string]::IsNullOrWhiteSpace($script:ResolvedServiceName)) {
        try {
            Start-Service -Name $script:ResolvedServiceName -ErrorAction SilentlyContinue
        } catch {
            # Keep fail/interrupt handlers quiet, like the OpenWRT script's 2>/dev/null.
        }
    }
}

function Remove-WorkDir {
    if (-not [string]::IsNullOrWhiteSpace($script:WorkDir) -and (Test-Path -LiteralPath $script:WorkDir)) {
        Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Restore-BackupIfNeeded {
    if (
        -not [string]::IsNullOrWhiteSpace($script:BackupPath) -and
        -not [string]::IsNullOrWhiteSpace($script:BackupOriginalPath) -and
        (Test-Path -LiteralPath $script:BackupPath -PathType Leaf)
    ) {
        try {
            Write-RawLine "${C}[*] Restoring previous version...${N}"
            Copy-Item -LiteralPath $script:BackupPath -Destination $script:BackupOriginalPath -Force
        } catch {
            Write-RawLine "${Y}[!] Failed to restore previous version from backup: $($script:BackupPath)${N}"
        }
    }
}

function Fail {
    param([string]$Message)

    Write-RawLine "${R}[!] ERROR: $Message${N}"
    Restore-BackupIfNeeded
    Remove-WorkDir
    Restart-StoppedService
    throw "Installation aborted: $Message"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Admin {
    param([string]$Message)

    if (-not (Test-IsAdmin)) {
        Fail "$Message Run PowerShell as administrator."
    }
}

function Resolve-DefaultDestFile {
    if (-not [string]::IsNullOrWhiteSpace($DestFile)) {
        return [System.IO.Path]::GetFullPath($DestFile)
    }

    if (Test-IsAdmin) {
        return Join-Path $env:ProgramFiles "sing-box-extended\sing-box.exe"
    }

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Fail "LOCALAPPDATA is not set. Specify path via -DestFile."
    }

    return Join-Path $env:LOCALAPPDATA "Programs\sing-box-extended\sing-box.exe"
}

function Resolve-ConfigFile {
    param([string]$ResolvedDestFile)

    if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
        return [System.IO.Path]::GetFullPath($ConfigFile)
    }

    return Join-Path (Split-Path -Parent $ResolvedDestFile) "config.json"
}

function Resolve-ServiceName {
    if (-not [string]::IsNullOrWhiteSpace($ServiceName)) {
        return $ServiceName
    }

    if (Get-Service -Name "podkop" -ErrorAction SilentlyContinue) {
        return "podkop"
    }

    if (Get-Service -Name "sing-box-extended" -ErrorAction SilentlyContinue) {
        return "sing-box-extended"
    }

    if (Get-Service -Name "sing-box" -ErrorAction SilentlyContinue) {
        return "sing-box"
    }

    return "sing-box-extended"
}

function Resolve-HostArchitecture {
    if (-not [string]::IsNullOrWhiteSpace($ArchSuffix)) {
        return [pscustomobject]@{
            HostArch = $ArchSuffix
            Suffix = $ArchSuffix
        }
    }

    $hostArch = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($hostArch)) {
        $hostArch = $env:PROCESSOR_ARCHITECTURE
    }

    switch -Regex ($hostArch) {
        "^(AMD64|IA64)$" {
            return [pscustomobject]@{
                HostArch = $hostArch
                Suffix = "amd64"
            }
        }
        "^ARM64$" {
            return [pscustomobject]@{
                HostArch = $hostArch
                Suffix = "arm64"
            }
        }
        "^(x86|X86|386)$" {
            return [pscustomobject]@{
                HostArch = $hostArch
                Suffix = "386"
            }
        }
        default {
            Write-RawLine "${R}[!] ERROR: Architecture $hostArch is not supported.${N}"
            exit 1
        }
    }
}

function Get-CurrentVersion {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ""
    }

    try {
        $line = & $Path version 2>$null | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($line)) {
            return ""
        }

        $parts = ([string]$line).Trim() -split "\s+"
        return $parts[-1]
    } catch {
        return ""
    }
}

function New-GitHubHeaders {
    return @{
        "User-Agent" = "sing-box-extended-windows-installer"
        "Accept" = "application/vnd.github+json"
    }
}

function Invoke-GitHubJson {
    param([string]$Uri)

    try {
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            return Invoke-RestMethod -Uri $Uri -Headers (New-GitHubHeaders) -TimeoutSec 15 -UseBasicParsing
        }

        return Invoke-RestMethod -Uri $Uri -Headers (New-GitHubHeaders) -TimeoutSec 15
    } catch {
        Fail "Failed to connect to GitHub API. Check your connection. Details: $($_.Exception.Message)"
    }
}

function Invoke-DownloadFile {
    param(
        [string]$Uri,
        [string]$OutFile
    )

    try {
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -Headers (New-GitHubHeaders) -TimeoutSec 15 -UseBasicParsing
        } else {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -Headers (New-GitHubHeaders) -TimeoutSec 15
        }
    } catch {
        Fail "Failed to download file. Details: $($_.Exception.Message)"
    }
}

function Get-FreeSpaceKB {
    param([string]$Path)

    try {
        $probe = $Path
        while (-not [string]::IsNullOrWhiteSpace($probe) -and -not (Test-Path -LiteralPath $probe)) {
            $parent = Split-Path -Parent $probe
            if ($parent -eq $probe) {
                break
            }
            $probe = $parent
        }

        if ([string]::IsNullOrWhiteSpace($probe)) {
            return 0
        }

        $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($probe))
        if ([string]::IsNullOrWhiteSpace($root)) {
            return 0
        }

        $driveName = $root.Substring(0, 1)
        $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
        return [int64]($drive.Free / 1KB)
    } catch {
        return 0
    }
}

function Stop-TargetService {
    param([string]$Name)

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) {
        return
    }

    $script:ServiceStopped = $true

    try {
        Stop-Service -Name $Name -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } catch {}
}

function Start-TargetService {
    param([string]$Name)

    try {
        Start-Service -Name $Name -ErrorAction SilentlyContinue
    } catch {}
}

function Install-OrUpdateService {
    param(
        [string]$Name,
        [string]$BinaryPath,
        [string]$ConfigPath
    )

    Require-Admin "Elevation is required to create a Windows Service."

    if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        Fail "Binary not found: $BinaryPath"
    }

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Fail "Configuration file for the service not found: $ConfigPath"
    }

    $existing = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-TargetService -Name $Name
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
        if ($service) {
            $service | Remove-CimInstance
        }
        Start-Sleep -Seconds 2
    }

    $binPath = "`"$BinaryPath`" -c `"$ConfigPath`" run"
    try {
        New-Service -Name $Name -BinaryPathName $binPath -StartupType Automatic -DisplayName "sing-box extended" -ErrorAction Stop | Out-Null
    } catch {
        Fail "Failed to create Windows Service. Details: $($_.Exception.Message)"
    }

    Write-RawLine "${G}[+] Windows Service created: ${Y}${Name}${N}"
}

function Remove-ServiceIfExists {
    param([string]$Name)

    Require-Admin "Elevation is required to remove Windows Service."

    $existing = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-RawLine "${Y}[!] Service not found: $Name${N}"
        return
    }

    Stop-TargetService -Name $Name
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($service) {
        try {
            $service | Remove-CimInstance -ErrorAction Stop
        } catch {
            Fail "Failed to remove Windows Service: $Name. Details: $($_.Exception.Message)"
        }
    }

    Write-RawLine "${G}[+] Windows Service removed: ${Y}${Name}${N}"
}

function Test-PathContainsDirectory {
    param(
        [string]$PathValue,
        [string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    $targetNorm = $Directory.Trim().Trim('"').TrimEnd("\").ToLowerInvariant()

    foreach ($entry in ($PathValue -split ";")) {
        if ($entry.Trim().Trim('"').TrimEnd("\").ToLowerInvariant() -eq $targetNorm) {
            return $true
        }
    }

    return $false
}

function Add-DestinationToPath {
    param(
        [string]$Directory,
        [switch]$Machine
    )

    $scope = if ($Machine) { "Machine" } else { "User" }

    if ($Machine) {
        Require-Admin "Elevation is required to add sing-box-extended to Machine PATH."
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    if (Test-PathContainsDirectory -PathValue $machinePath -Directory $Directory) {
        Write-RawLine "${C}[*] sing-box-extended is already in Machine PATH: ${Y}${Directory}${N}"
        return
    }

    if (Test-PathContainsDirectory -PathValue $userPath -Directory $Directory) {
        Write-RawLine "${C}[*] sing-box-extended is already in User PATH: ${Y}${Directory}${N}"
        return
    }

    $current = [Environment]::GetEnvironmentVariable("Path", $scope)
    $currentClean = if ($current) { $current.Trim().TrimEnd(';') } else { "" }
    $newPath = if ([string]::IsNullOrWhiteSpace($currentClean)) { $Directory } else { "$currentClean;$Directory" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)

    Write-RawLine "${G}[+] sing-box-extended added to $scope PATH: ${Y}${Directory}${N}"
    Write-RawLine "${Y}[!] Already opened terminals may not see the updated PATH until restarted.${N}"
}

function Backup-ExistingBinary {
    param([string]$Path)

    $script:BackupPath = ""
    $script:BackupOriginalPath = ""

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$Path.bak.$timestamp"

    try {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        $script:BackupPath = $backupPath
        $script:BackupOriginalPath = $Path
        Write-RawLine "${C}[*] Backup of the old binary created: ${Y}${backupPath}${N}"

        # Cleanup old backups
        $parentDir = Split-Path -Parent $Path
        $bakPrefix = (Split-Path -Leaf $Path) + ".bak."
        $oldBackups = Get-ChildItem -LiteralPath $parentDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$bakPrefix*" } |
            Sort-Object LastWriteTime -Descending

        if ($oldBackups.Count -gt 5) {
            $oldBackups | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Fail "Failed to create backup of the old binary. Details: $($_.Exception.Message)"
    }
}

function Import-ConfigIfRequested {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$BinaryPath
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return $TargetPath
    }

    $sourceFullPath = [System.IO.Path]::GetFullPath($SourcePath)

    if (-not (Test-Path -LiteralPath $sourceFullPath -PathType Leaf)) {
        Fail "Configuration file for import not found: $sourceFullPath"
    }

    $targetDir = Split-Path -Parent $TargetPath
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    Write-RawLine "${C}[*] Importing config: ${Y}${sourceFullPath}${N}"
    try {
        Copy-Item -LiteralPath $sourceFullPath -Destination $TargetPath -Force
    } catch {
        Fail "Failed to import config to $TargetPath"
    }

    if (Test-Path -LiteralPath $BinaryPath -PathType Leaf) {
        Test-SingBoxConfig -BinaryPath $BinaryPath -ConfigPath $TargetPath
    }

    return $TargetPath
}

function New-DefaultSingBoxConfig {
    param([string]$Path)

    $content = @'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 7890,
      "set_system_proxy": false
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
'@

    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Open-JsonEditorAndWait {
    param([string]$Path)

    Write-RawLine "${C}[*] Opening config in default JSON editor...${N}"
    Write-RawLine "${Y}[!] Save the file and close the editor to continue.${N}"

    try {
        Start-Process -FilePath $Path -Wait -ErrorAction Stop
    } catch {
        Write-RawLine "${Y}[!] Failed to open default editor. Opening Notepad...${N}"
        Start-Process -FilePath "notepad.exe" -ArgumentList "`"$Path`"" -Wait
    }
}

function Test-SingBoxConfig {
    param(
        [string]$BinaryPath,
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Fail "Configuration file not found: $ConfigPath"
    }

    Write-RawLine "${C}[*] Checking configuration...${N}"
    & $BinaryPath -c $ConfigPath check

    if ($LASTEXITCODE -ne 0) {
        Fail "Configuration check failed."
    }

    Write-RawLine "${G}[+] Configuration is valid.${N}"
}

function Invoke-SingBoxRun {
    param(
        [string]$BinaryPath,
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        Fail "Binary not found: $BinaryPath"
    }

    $service = Get-Service -Name $script:ResolvedServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-RawLine "${Y}[!] Service $($script:ResolvedServiceName) is already running. Manual run might cause port conflicts.${N}"
        Write-Raw "${C}[?] Stop service before manual run? [y/N]: ${N}"
        $stopAnswer = Read-Host
        if (Test-Yes $stopAnswer) {
            Stop-TargetService -Name $script:ResolvedServiceName
        }
    }

    Test-SingBoxConfig -BinaryPath $BinaryPath -ConfigPath $ConfigPath

    Write-RawLine "${C}[*] Starting sing-box extended...${N}"
    Write-RawLine "${Y}[!] Press Ctrl+C to stop.${N}"
    & $BinaryPath -c $ConfigPath run
}

function Select-RunConfig {
    param(
        [string]$BinaryPath,
        [string]$DefaultConfigPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ImportConfig)) {
        return Import-ConfigIfRequested -SourcePath $ImportConfig -TargetPath $DefaultConfigPath -BinaryPath $BinaryPath
    }

    if (-not [string]::IsNullOrWhiteSpace($ConfigFile) -and (Test-Path -LiteralPath $DefaultConfigPath -PathType Leaf)) {
        return $DefaultConfigPath
    }

    Write-RawLine ""
    Write-RawLine "${C}[*] Select configuration to run:${N}"
    Write-RawLine "  ${Y}1)${N} Specify path to an existing configuration file"
    Write-RawLine "  ${Y}2)${N} Create a new configuration file (default_config.json)"
    Write-RawLine "  ${Y}0)${N} Cancel running sing-box-extended"
    Write-Raw ""
    Write-Raw "${C}[?] Choose option (0-2): ${N}"
    $choice = Read-Host

    switch ($choice) {
        "0" {
            Write-RawLine "${G}[*] Start cancelled.${N}"
            return ""
        }
        "1" {
            Write-Raw "${C}[?] Specify full path to config.json: ${N}"
            $path = Read-Host
            $path = [System.IO.Path]::GetFullPath($path.Trim('"'))

            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Fail "Configuration file not found: $path"
            }

            return $path
        }
        "2" {
            $defaultConfig = Join-Path (Split-Path -Parent $BinaryPath) "default_config.json"
            if (-not (Test-Path -LiteralPath $defaultConfig -PathType Leaf)) {
                New-DefaultSingBoxConfig -Path $defaultConfig
                Write-RawLine "${G}[+] Config created: ${Y}${defaultConfig}${N}"
            } else {
                Write-RawLine "${Y}[!] File already exists: $defaultConfig${N}"
            }

            Open-JsonEditorAndWait -Path $defaultConfig
            return $defaultConfig
        }
        default {
            Fail "Invalid choice. Please enter a valid number from the list."
        }
    }
}

function Offer-RunAfterInstall {
    param(
        [string]$BinaryPath,
        [string]$DefaultConfigPath
    )

    if ($NoRunPrompt) {
        return
    }

    if ($RunNow) {
        $selectedConfig = Select-RunConfig -BinaryPath $BinaryPath -DefaultConfigPath $DefaultConfigPath
        if (-not [string]::IsNullOrWhiteSpace($selectedConfig)) {
            Invoke-SingBoxRun -BinaryPath $BinaryPath -ConfigPath $selectedConfig
        }
        return
    }

    if ($RunAfterInstallPrompt -or -not $NoRunPrompt) {
        Write-Raw ""
        Write-Raw "${C}[?] Start sing-box extended now? [y/N]: ${N}"
        $answer = Read-Host
        if (Test-Yes $answer) {
            $selectedConfig = Select-RunConfig -BinaryPath $BinaryPath -DefaultConfigPath $DefaultConfigPath
            if (-not [string]::IsNullOrWhiteSpace($selectedConfig)) {
                Invoke-SingBoxRun -BinaryPath $BinaryPath -ConfigPath $selectedConfig
            }
        }
    }
}

function Invoke-Uninstall {
    param(
        [string]$BinaryPath
    )

    if (Get-Service -Name $script:ResolvedServiceName -ErrorAction SilentlyContinue) {
        Stop-TargetService -Name $script:ResolvedServiceName
    }

    if (Test-Path -LiteralPath $BinaryPath -PathType Leaf) {
        try {
            Remove-Item -LiteralPath $BinaryPath -Force
            Write-RawLine "${G}[+] Binary deleted: ${Y}${BinaryPath}${N}"
        } catch {
            Fail "Failed to delete binary: $BinaryPath"
        }
    } else {
        Write-RawLine "${Y}[!] Binary not found: $BinaryPath${N}"
    }
}

function Invoke-InstallOrUpdate {
    param(
        [string]$ResolvedDestFile,
        [string]$ResolvedConfigFile,
        [object]$Arch
    )

    $currentVer = Get-CurrentVersion -Path $ResolvedDestFile

    Write-RawLine "${C}[*] Retrieving latest versions...${N}"
    $apiResponse = Invoke-GitHubJson -Uri $ApiUrl

    $releases = @(
        $apiResponse |
            Where-Object {
                $_.tag_name -and
                $_.tag_name -notmatch "(?i)rc" -and
                $_.tag_name -notmatch "(?i)beta" -and
                $_.tag_name -notmatch "(?i)alpha"
            } |
            Select-Object -First 5
    )

    if ($releases.Count -eq 0) {
        Fail "Failed to retrieve stable releases from API."
    }

    Write-RawLine ""
    Write-RawLine "${C}[*] Available stable versions for installation:${N}"

    $i = 1
    foreach ($releaseItem in $releases) {
        Write-RawLine "  ${Y}$i)${N} $($releaseItem.tag_name)"
        $i++
    }
    Write-RawLine "  ${Y}0)${N} Cancel"

    Write-Raw ""
    Write-Raw "${C}[?] Choose version (0-$($i - 1)): ${N}"
    $choice = Read-Host

    if ($choice -eq "0") {
        Write-RawLine "${G}[*] Installation cancelled.${N}"
        exit 0
    }

    [int]$choiceNumber = 0
    if (-not [int]::TryParse($choice, [ref]$choiceNumber)) {
        Fail "Invalid choice. Please enter a valid number from the list."
    }

    if ($choiceNumber -lt 1 -or $choiceNumber -gt $releases.Count) {
        Fail "Invalid choice. Please enter a valid number from the list."
    }

    $selectedTag = $releases[$choiceNumber - 1].tag_name
    $selectedVer = $selectedTag -replace "^v", ""

    Write-RawLine ""
    Write-RawLine "${C}[*] Current: ${Y}$(if ($currentVer) { $currentVer } else { "not installed" })${C} | Selected: ${Y}${selectedVer}${N}"

    if (-not [string]::IsNullOrWhiteSpace($currentVer) -and $currentVer -eq $selectedVer) {
        if ($ForceReinstall) {
            Write-RawLine "${Y}[!] This version is already installed. Performing reinstallation...${N}"
        } else {
            Write-RawLine "${Y}[!] This version is already installed.${N}"
            Write-Raw "${C}[?] Reinstall? [y/N]: ${N}"
            $reinstallAnswer = Read-Host

            if (-not (Test-Yes $reinstallAnswer)) {
                Write-RawLine "${G}[+] Selected version is already installed. Reinstallation is not required.${N}"

                $importedConfig = Import-ConfigIfRequested -SourcePath $ImportConfig -TargetPath $ResolvedConfigFile -BinaryPath $ResolvedDestFile
                Offer-RunAfterInstall -BinaryPath $ResolvedDestFile -DefaultConfigPath $importedConfig
                exit 0
            }
        }
    }

    Write-RawLine "${C}[*] Searching download link for version $selectedTag...${N}"

    $releaseUrl = "$ReleaseApiBase/$selectedTag"
    $releaseResponse = Invoke-GitHubJson -Uri $releaseUrl

    $filePattern = "windows-$($Arch.Suffix)\.zip$"
    $asset = @(
        $releaseResponse.assets |
            Where-Object {
                $_.browser_download_url -and
                $_.name -match $filePattern -and
                $_.name -notmatch "(?i)legacy"
            } |
            Select-Object -First 1
    )

    if ($asset.Count -eq 0) {
        $asset = @(
            $releaseResponse.assets |
                Where-Object {
                    $_.browser_download_url -and
                    $_.name -match $filePattern
                } |
                Select-Object -First 1
        )
    }

    if ($asset.Count -eq 0) {
        Fail "File for architecture '$($Arch.HostArch)' ($($Arch.Suffix)) not found in release $selectedTag."
    }

    $downloadUrl = $asset[0].browser_download_url

    $reqTempKB = 81920
    $reqDestKB = 61440

    $resolvedDestDir = Split-Path -Parent $ResolvedDestFile
    $destFreeKB = Get-FreeSpaceKB -Path $resolvedDestDir
    $existingSizeKB = 0

    if (Test-Path -LiteralPath $ResolvedDestFile -PathType Leaf) {
        $existingSizeKB = [int64]((Get-Item -LiteralPath $ResolvedDestFile).Length / 1KB)
    }

    $totalDestAvailableKB = $destFreeKB + $existingSizeKB

    if ($totalDestAvailableKB -lt $reqDestKB) {
        Fail "Insufficient space in $resolvedDestDir. Available: $([int]($totalDestAvailableKB / 1024)) MB, required: $([int]($reqDestKB / 1024)) MB."
    }

    $tempParent = if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) { $env:TEMP } else { $env:TMP }
    if ([string]::IsNullOrWhiteSpace($tempParent)) {
        $tempParent = $resolvedDestDir
    }

    $tempFreeKB = Get-FreeSpaceKB -Path $tempParent
    if ($tempFreeKB -lt $reqTempKB) {
        Fail "Insufficient free space for installation. Available in ${tempParent}: $([int]($tempFreeKB / 1024)) MB. Minimum required: $([int]($reqTempKB / 1024)) MB."
    }

    $script:WorkDir = Join-Path $tempParent "sing-box-install"

    Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    Push-Location $script:WorkDir

    try {
        Write-RawLine "${C}[*] Downloading and installing...${N}"

        $archivePath = Join-Path $script:WorkDir $ArchiveName
        Invoke-DownloadFile -Uri $downloadUrl -OutFile $archivePath

        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or (Get-Item -LiteralPath $archivePath).Length -le 0) {
            Fail "Downloaded file is empty."
        }

        Stop-TargetService -Name $script:ResolvedServiceName
        Backup-ExistingBinary -Path $ResolvedDestFile

        $extractDir = Join-Path $script:WorkDir "extract"
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

        try {
            Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDir -Force
        } catch {
            Fail "Failed to extract archive."
        }

        Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue

        $binaryPath = Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter "sing-box.exe" |
            Select-Object -First 1

        if (-not $binaryPath) {
            Fail "Binary not found in archive."
        }

        New-Item -ItemType Directory -Path $resolvedDestDir -Force | Out-Null

        try {
            Copy-Item -LiteralPath $binaryPath.FullName -Destination $ResolvedDestFile -Force
        } catch {
            Fail "Failed to replace file."
        }

        if (-not $NoAddToPath) {
            Add-DestinationToPath -Directory $resolvedDestDir -Machine:$AddToMachinePath
        }

        $effectiveConfigFile = Import-ConfigIfRequested -SourcePath $ImportConfig -TargetPath $ResolvedConfigFile -BinaryPath $ResolvedDestFile

        if ($CreateService) {
            Install-OrUpdateService -Name $script:ResolvedServiceName -BinaryPath $ResolvedDestFile -ConfigPath $effectiveConfigFile
        }

        $newVersion = Get-CurrentVersion -Path $ResolvedDestFile
        if ([string]::IsNullOrWhiteSpace($newVersion)) {
            Fail "Failed to check the new version of the installed binary."
        }

        $script:BackupPath = ""
        $script:BackupOriginalPath = ""
    } finally {
        Pop-Location
    }

    Remove-WorkDir
    $script:WorkDir = ""

    $script:ServiceStopped = $false
    Start-TargetService -Name $script:ResolvedServiceName

    Write-RawLine "${G}[+] Done: ${Y}$(if ($currentVer) { $currentVer } else { "N/A" })${G} -> ${Y}$(if ($newVersion) { $newVersion } else { "N/A" })${N}"

    Offer-RunAfterInstall -BinaryPath $ResolvedDestFile -DefaultConfigPath $effectiveConfigFile
}

try {
    # Enable TLS 1.2 and TLS 1.3 (code 12288 for .NET 4.5/4.7 where [Net.SecurityProtocolType]::Tls13 is absent)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 -bor 12288
} catch {}

$resolvedDestFile = Resolve-DefaultDestFile
$resolvedDestDir = Split-Path -Parent $resolvedDestFile
$resolvedConfigFile = Resolve-ConfigFile -ResolvedDestFile $resolvedDestFile
$script:ResolvedServiceName = Resolve-ServiceName
$arch = Resolve-HostArchitecture

if ($resolvedDestDir.StartsWith($env:ProgramFiles, [System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-IsAdmin)) {
    Fail "To install in Program Files, run PowerShell as administrator."
}

switch ($Action) {
    "Install" {
        Invoke-InstallOrUpdate -ResolvedDestFile $resolvedDestFile -ResolvedConfigFile $resolvedConfigFile -Arch $arch
    }
    "Update" {
        Invoke-InstallOrUpdate -ResolvedDestFile $resolvedDestFile -ResolvedConfigFile $resolvedConfigFile -Arch $arch
    }
    "Uninstall" {
        Invoke-Uninstall -BinaryPath $resolvedDestFile
    }
    "Run" {
        $effectiveConfigFile = Import-ConfigIfRequested -SourcePath $ImportConfig -TargetPath $resolvedConfigFile -BinaryPath $resolvedDestFile
        if ([string]::IsNullOrWhiteSpace($ImportConfig) -and [string]::IsNullOrWhiteSpace($ConfigFile)) {
            $effectiveConfigFile = Select-RunConfig -BinaryPath $resolvedDestFile -DefaultConfigPath $resolvedConfigFile
        }

        if (-not [string]::IsNullOrWhiteSpace($effectiveConfigFile)) {
            Invoke-SingBoxRun -BinaryPath $resolvedDestFile -ConfigPath $effectiveConfigFile
        }
    }
    "ServiceInstall" {
        $effectiveConfigFile = Import-ConfigIfRequested -SourcePath $ImportConfig -TargetPath $resolvedConfigFile -BinaryPath $resolvedDestFile
        Install-OrUpdateService -Name $script:ResolvedServiceName -BinaryPath $resolvedDestFile -ConfigPath $effectiveConfigFile
    }
    "ServiceRemove" {
        Remove-ServiceIfExists -Name $script:ResolvedServiceName
    }
}
