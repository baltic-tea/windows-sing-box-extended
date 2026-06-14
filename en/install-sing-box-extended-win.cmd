@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

:: Default settings
set "ACTION=Install"
set "DEST_FILE="
set "CONFIG_FILE="
set "SERVICE_NAME="
set "CREATE_SERVICE=0"
set "RUN_NOW=0"
set "RUN_AFTER_INSTALL_PROMPT=0"
set "NO_RUN_PROMPT=0"
set "FORCE_REINSTALL=0"
set "IMPORT_CONFIG="
set "NO_ADD_TO_PATH=0"
set "ADD_TO_MACHINE_PATH=0"
set "ARCH_SUFFIX="
set "NO_COLOR=0"

:: 1. Parse arguments
:parse_args
if "%~1"=="" goto end_parse_args
set "arg=%~1"
set "val=%~2"
set "prefix=!arg:~0,1!"
if "!prefix!"=="-" (
    set "name=!arg:~1!"
) else if "!prefix!"=="/" (
    set "name=!arg:~1!"
) else (
    shift
    goto parse_args
)

if /i "!name!"=="Action" set "ACTION=!val!" & shift & shift & goto parse_args
if /i "!name!"=="DestFile" set "DEST_FILE=!val!" & shift & shift & goto parse_args
if /i "!name!"=="ConfigFile" set "CONFIG_FILE=!val!" & shift & shift & goto parse_args
if /i "!name!"=="ServiceName" set "SERVICE_NAME=!val!" & shift & shift & goto parse_args
if /i "!name!"=="CreateService" set "CREATE_SERVICE=1" & shift & goto parse_args
if /i "!name!"=="RunNow" set "RUN_NOW=1" & shift & goto parse_args
if /i "!name!"=="RunAfterInstallPrompt" set "RUN_AFTER_INSTALL_PROMPT=1" & shift & goto parse_args
if /i "!name!"=="NoRunPrompt" set "NO_RUN_PROMPT=1" & shift & goto parse_args
if /i "!name!"=="ForceReinstall" set "FORCE_REINSTALL=1" & shift & goto parse_args
if /i "!name!"=="ImportConfig" set "IMPORT_CONFIG=!val!" & shift & shift & goto parse_args
if /i "!name!"=="NoAddToPath" set "NO_ADD_TO_PATH=1" & shift & goto parse_args
if /i "!name!"=="NoAddToUserPath" set "NO_ADD_TO_PATH=1" & shift & goto parse_args
if /i "!name!"=="AddToMachinePath" set "ADD_TO_MACHINE_PATH=1" & shift & goto parse_args
if /i "!name!"=="ArchSuffix" set "ARCH_SUFFIX=!val!" & shift & shift & goto parse_args
if /i "!name!"=="NoColor" set "NO_COLOR=1" & shift & goto parse_args

shift
goto parse_args
:end_parse_args

:: Enable ANSI colors if supported and not disabled
if "!NO_COLOR!"=="1" (
    set "R=" & set "G=" & set "Y=" & set "C=" & set "N="
) else (
    reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1
    for /F "delims=#" %%a in ('"prompt $E# & echo on & for %%b in (1) do rem"') do set "ESC=%%a"
    set "R=!ESC![1;31m"
    set "G=!ESC![1;32m"
    set "Y=!ESC![1;33m"
    set "C=!ESC![1;36m"
    set "N=!ESC![0m"
)

:: Check administrator privileges
net session >nul 2>&1
if %ERRORLEVEL% == 0 (
    set "IS_ADMIN=1"
) else (
    set "IS_ADMIN=0"
)

:: Resolve paths
if "!DEST_FILE!"=="" (
    if "!IS_ADMIN!"=="1" (
        set "DEST_FILE=%ProgramFiles%\sing-box-extended\sing-box.exe"
    ) else (
        if "%LOCALAPPDATA%"=="" (
            echo %R%[^^!] ERROR: LOCALAPPDATA is not set. Specify path via -DestFile.%N%
            exit /b 1
        )
        set "DEST_FILE=%LOCALAPPDATA%\Programs\sing-box-extended\sing-box.exe"
    )
)
:: Convert DEST_FILE to absolute path
for %%i in ("!DEST_FILE!") do set "DEST_FILE=%%~fi"
for %%i in ("!DEST_FILE!") do set "DEST_DIR=%%~dpi"
set "DEST_DIR=!DEST_DIR:~0,-1!"

if "!CONFIG_FILE!"=="" (
    set "CONFIG_FILE=!DEST_DIR!\config.json"
) else (
    for %%i in ("!CONFIG_FILE!") do set "CONFIG_FILE=%%~fi"
)

:: Resolve Service Name
if "!SERVICE_NAME!"=="" (
    powershell -NoProfile -Command "$s1=Get-Service podkop -EA SilentlyContinue; $name = if ($s1) { 'podkop' } else { $s2=Get-Service sing-box-extended -EA SilentlyContinue; if ($s2) { 'sing-box-extended' } else { $s3=Get-Service sing-box -EA SilentlyContinue; if ($s3) { 'sing-box' } else { 'sing-box-extended' } } }; $name | Out-File -LiteralPath ($env:TEMP + '\resolved_service.txt') -NoNewline -Encoding ascii"
    if exist "%TEMP%\resolved_service.txt" (
        set /p RESOLVED_SERVICE=<"%TEMP%\resolved_service.txt"
        del /f /q "%TEMP%\resolved_service.txt"
    ) else (
        set "RESOLVED_SERVICE=sing-box-extended"
    )
) else (
    set "RESOLVED_SERVICE=!SERVICE_NAME!"
)

:: Ensure Program Files install has admin rights
echo "!DEST_DIR!" | findstr /i /c:"%ProgramFiles%" >nul
if %ERRORLEVEL% == 0 (
    if "!IS_ADMIN!"=="0" (
        echo %R%[^^!] ERROR: To install in Program Files, run the script as administrator.%N%
        exit /b 1
    )
)

:: Resolve Architecture
if "!ARCH_SUFFIX!"=="" (
    set "HOST_ARCH=%PROCESSOR_ARCHITEW6432%"
    if "!HOST_ARCH!"=="" set "HOST_ARCH=%PROCESSOR_ARCHITECTURE%"

    if /i "!HOST_ARCH!"=="AMD64" (
        set "ARCH_SUFFIX=amd64"
    ) else if /i "!HOST_ARCH!"=="ARM64" (
        set "ARCH_SUFFIX=arm64"
    ) else if /i "!HOST_ARCH!"=="x86" (
        set "ARCH_SUFFIX=386"
    ) else (
        echo %R%[^^!] ERROR: Architecture !HOST_ARCH! is not supported.%N%
        exit /b 1
    )
)

:: Dispatch actions
if /i "%ACTION%"=="Install" goto Action_InstallOrUpdate
if /i "%ACTION%"=="Update" goto Action_InstallOrUpdate
if /i "%ACTION%"=="Uninstall" goto Action_Uninstall
if /i "%ACTION%"=="Run" goto Action_Run
if /i "%ACTION%"=="ServiceInstall" goto Action_ServiceInstall
if /i "%ACTION%"=="ServiceRemove" goto Action_ServiceRemove

echo %R%[^^!] ERROR: Unknown action "%ACTION%"%N%
exit /b 1


:: Action: Install or Update
:Action_InstallOrUpdate
:: Get current version
set "CURRENT_VER="
if exist "!DEST_FILE!" (
    set "ENV_DEST_FILE=!DEST_FILE!"
    powershell -NoProfile -Command "try { $lines = @(& $env:ENV_DEST_FILE version 2>$null); if ($lines.Count -gt 0) { $v = $lines[0] -split '\s+'; $v[-1] | Out-File -LiteralPath ($env:TEMP + '\current_ver.txt') -NoNewline -Encoding ascii } } catch {}"
    if exist "%TEMP%\current_ver.txt" (
        set /p CURRENT_VER=<"%TEMP%\current_ver.txt"
        del /f /q "%TEMP%\current_ver.txt"
    )
)

echo %C%[*] Retrieving latest versions...%N%
:: Query GitHub releases (top 5 stable ones)
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = 15360; $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/shtorm-7/sing-box-extended/releases?per_page=30' -Headers @{'User-Agent'='sing-box'}; $stable = $r | Where-Object { $_.tag_name -and $_.tag_name -notmatch 'rc' -and $_.tag_name -notmatch 'beta' -and $_.tag_name -notmatch 'alpha' } | Select-Object -First 5; $i=1; $outLines = $stable | ForEach-Object { $out = $i, $_.tag_name -join ','; $i++; $out }; $outLines | Out-File -LiteralPath ($env:TEMP + '\releases_list.txt') -Encoding ascii"

set "count=0"
if exist "%TEMP%\releases_list.txt" (
    for /f "usebackq tokens=1,2 delims=," %%a in ("%TEMP%\releases_list.txt") do (
        set "REL_%%a=%%b"
        set "count=%%a"
        echo   %Y%%%a%N%^) %%b
    )
    del /f /q "%TEMP%\releases_list.txt"
)

if "!count!"=="0" (
    echo %R%[^^!] ERROR: Failed to retrieve stable releases.%N%
    exit /b 1
)
echo   %Y%0%N%) Cancel
echo.

:prompt_version
set "choice="
set /p "choice=%C%[?] Choose version (0-!count!): %N%"
if "!choice!"=="0" (
    echo %G%[*] Installation cancelled.%N%
    exit /b 0
)
if "!choice!"=="" goto prompt_version
set "SELECTED_TAG=!REL_%choice%!"
if "!SELECTED_TAG!"=="" (
    echo %R%[^^!] Invalid choice.%N%
    goto prompt_version
)

set "SELECTED_VER=!SELECTED_TAG!"
if "!SELECTED_VER:~0,1!"=="v" set "SELECTED_VER=!SELECTED_VER:~1!"

echo.
if "!CURRENT_VER!"=="" (
    set "disp_curr=not installed"
) else (
    set "disp_curr=!CURRENT_VER!"
)
echo %C%[*] Current: %Y%!disp_curr!%C% ^| Selected: %Y%!SELECTED_VER!%N%

if "!CURRENT_VER!"=="!SELECTED_VER!" (
    if "!FORCE_REINSTALL!"=="1" (
        echo %Y%[^^!] This version is already installed. Performing reinstallation...%N%
    ) else (
        echo %Y%[^^!] This version is already installed.%N%
        set /p "reins_choice=%C%[?] Reinstall? [y/N]: %N%"
        if /i "!reins_choice!"=="y" goto do_install
        if /i "!reins_choice!"=="yes" goto do_install

        echo %G%[+] Selected version is already installed. Reinstallation is not required.%N%
        if not "!IMPORT_CONFIG!"=="" call :ImportConfigHelper
        goto Action_OfferRun
    )
)

:do_install
echo %C%[*] Searching download link for version !SELECTED_TAG!...%N%
set "ENV_SELECTED_TAG=!SELECTED_TAG!"
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = 15360; $r = Invoke-RestMethod -Uri \"https://api.github.com/repos/shtorm-7/sing-box-extended/releases/tags/$env:ENV_SELECTED_TAG\" -Headers @{'User-Agent'='sing-box'}; $all_assets = $r.assets; $a = $all_assets | Where-Object { $_.name -match 'windows-%ARCH_SUFFIX%\.zip$' -and $_.name -notmatch 'legacy' }; if (-not $a) { $a = $all_assets | Where-Object { $_.name -match 'windows-%ARCH_SUFFIX%\.zip$' } }; if ($a) { $a[0].browser_download_url | Out-File -LiteralPath ($env:TEMP + '\download_url.txt') -NoNewline -Encoding ascii }"
if exist "%TEMP%\download_url.txt" (
    set /p DOWNLOAD_URL=<"%TEMP%\download_url.txt"
    del /f /q "%TEMP%\download_url.txt"
)

if "!DOWNLOAD_URL!"=="" (
    echo %R%[^^!] ERROR: File for architecture '%ARCH_SUFFIX%' not found.%N%
    exit /b 1
)

:: Disk space check
powershell -NoProfile -Command "$drive = Get-PSDrive -Name ('!DEST_DIR!'.Substring(0, 1)) -ErrorAction SilentlyContinue; if ($drive -and ($drive.Free / 1KB) -lt 61440) { exit 1 } else { exit 0 }"
if %ERRORLEVEL% neq 0 (
    echo %R%[^^!] ERROR: Insufficient free space in destination folder.%N%
    exit /b 1
)

set "TEMP_DIR=%TEMP%\sing-box-install-%random%"
if exist "!TEMP_DIR!" rd /s /q "!TEMP_DIR!"
md "!TEMP_DIR!"

echo %C%[*] Downloading and installing...%N%
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = 15360; Invoke-WebRequest -Uri '!DOWNLOAD_URL!' -OutFile '!TEMP_DIR!\sing-box.zip' -Headers @{'User-Agent'='sing-box'}"
if not exist "!TEMP_DIR!\sing-box.zip" (
    echo %R%[^^!] ERROR: Failed to download file.%N%
    rd /s /q "!TEMP_DIR!"
    exit /b 1
)

:: Stop target service
powershell -NoProfile -Command "Stop-Service -Name '%RESOLVED_SERVICE%' -ErrorAction SilentlyContinue"

:: Backup binary
if exist "!DEST_FILE!" (
    powershell -NoProfile -Command "$Path = '!DEST_FILE!'; $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'; $backupPath = \"$Path.bak.$timestamp\"; Copy-Item -LiteralPath $Path -Destination $backupPath -Force; $parentDir = Split-Path -Parent $Path; $bakPrefix = (Split-Path -Leaf $Path) + '.bak.'; $oldBackups = Get-ChildItem -LiteralPath $parentDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like \"$bakPrefix*\" } | Sort-Object LastWriteTime -Descending; if ($oldBackups.Count -gt 5) { $oldBackups | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue }"
    echo %C%[*] Backup of the old binary created.%N%
)

:: Unzip and Copy binary using a single robust PowerShell block via environment variables to bypass CMD syntax parser limits
set "ENV_ZIP_PATH=!TEMP_DIR!\sing-box.zip"
set "ENV_EXTRACT_DIR=!TEMP_DIR!\extract"
set "ENV_DEST_FILE=!DEST_FILE!"
set "ENV_DEST_DIR=!DEST_DIR!"
set "ENV_ERR_LOG=!TEMP_DIR!\install_error.log"

powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; try { Expand-Archive -LiteralPath $env:ENV_ZIP_PATH -DestinationPath $env:ENV_EXTRACT_DIR -Force; $f = Get-ChildItem -LiteralPath $env:ENV_EXTRACT_DIR -Recurse -Filter 'sing-box.exe' -ErrorAction SilentlyContinue; if (-not $f) { throw 'File sing-box.exe not found in extracted archive.' }; if (-not (Test-Path -LiteralPath $env:ENV_DEST_DIR)) { $null = New-Item -ItemType Directory -Path $env:ENV_DEST_DIR -Force }; Copy-Item -LiteralPath $f[0].FullName -Destination $env:ENV_DEST_FILE -Force } catch { $_.Exception.Message | Out-File -LiteralPath $env:ENV_ERR_LOG -Encoding utf8; exit 1 }"

if %ERRORLEVEL% neq 0 (
    echo %R%[^^!] ERROR: Failed to extract or install binary.%N%
    if exist "!TEMP_DIR!\install_error.log" (
        echo %R%Error details:%N%
        type "!TEMP_DIR!\install_error.log"
        echo.
    )
    rd /s /q "!TEMP_DIR!"
    exit /b 1
)

:: Add to PATH
if "!NO_ADD_TO_PATH!"=="0" (
    if "!ADD_TO_MACHINE_PATH!"=="1" (
        powershell -NoProfile -Command "$dir = '!DEST_DIR!'; $current = [Environment]::GetEnvironmentVariable('Path', 'Machine'); $clean = if ($current) { $current.Trim().TrimEnd(';') } else { '' }; if ($clean -notlike '*'+$dir+'*') { [Environment]::SetEnvironmentVariable('Path', $clean + ';' + $dir, 'Machine'); Write-Output '1' } else { Write-Output '0' }" > "!TEMP_DIR!\path_res.txt"
        set /p path_added=<"!TEMP_DIR!\path_res.txt"
        if "!path_added!"=="1" (
            echo %G%[+] sing-box-extended added to Machine PATH: !DEST_DIR!%N%
        )
    ) else (
        powershell -NoProfile -Command "$dir = '!DEST_DIR!'; $current = [Environment]::GetEnvironmentVariable('Path', 'User'); $clean = if ($current) { $current.Trim().TrimEnd(';') } else { '' }; if ($clean -notlike '*'+$dir+'*') { [Environment]::SetEnvironmentVariable('Path', $clean + ';' + $dir, 'User'); Write-Output '1' } else { Write-Output '0' }" > "!TEMP_DIR!\path_res.txt"
        set /p path_added=<"!TEMP_DIR!\path_res.txt"
        if "!path_added!"=="1" (
            echo %G%[+] sing-box-extended added to User PATH: !DEST_DIR!%N%
        )
    )
)

if not "!IMPORT_CONFIG!"=="" call :ImportConfigHelper

:: Create service
if "!CREATE_SERVICE!"=="1" (
    powershell -NoProfile -Command "Stop-Service -Name '%RESOLVED_SERVICE%' -ErrorAction SilentlyContinue"
    powershell -NoProfile -Command "$service = Get-CimInstance -ClassName Win32_Service -Filter \"Name='%RESOLVED_SERVICE%'\" -ErrorAction SilentlyContinue; if ($service) { $service | Remove-CimInstance }"
    Start-Sleep -Seconds 2
    powershell -NoProfile -Command "New-Service -Name '%RESOLVED_SERVICE%' -BinaryPathName '\"!DEST_FILE!\" -c \"!CONFIG_FILE!\" run' -StartupType Automatic -DisplayName 'sing-box extended' -ErrorAction Stop | Out-Null"
    if %ERRORLEVEL% neq 0 (
        echo %R%[^^!] ERROR: Failed to create Windows Service.%N%
    ) else (
        echo %G%[+] Windows Service created: %RESOLVED_SERVICE%%N%
    )
)

:: Restart service
powershell -NoProfile -Command "Start-Service -Name '%RESOLVED_SERVICE%' -ErrorAction SilentlyContinue"

rd /s /q "!TEMP_DIR!"

:: Get installed version for final message
set "NEW_VER="
if exist "!DEST_FILE!" (
    set "ENV_DEST_FILE=!DEST_FILE!"
    powershell -NoProfile -Command "try { $lines = @(& $env:ENV_DEST_FILE version 2>$null); if ($lines.Count -gt 0) { $v = $lines[0] -split '\s+'; $v[-1] | Out-File -LiteralPath ($env:TEMP + '\new_ver.txt') -NoNewline -Encoding ascii } } catch {}"
    if exist "%TEMP%\new_ver.txt" (
        set /p NEW_VER=<"%TEMP%\new_ver.txt"
        del /f /q "%TEMP%\new_ver.txt"
    )
)

set "disp_new=!NEW_VER!"
if "!disp_new!"=="" set "disp_new=N/A"
echo %G%[+] Done: !disp_curr! -^> !disp_new!%N%

:Action_OfferRun
if "!NO_RUN_PROMPT!"=="1" exit /b 0
if "!RUN_NOW!"=="1" goto start_singbox_process

set /p "run_ans=%C%[?] Start sing-box extended now? [y/N]: %N%"
if /i "!run_ans!"=="y" goto start_singbox_process
if /i "!run_ans!"=="yes" goto start_singbox_process
exit /b 0

:start_singbox_process
call :SelectAndRunConfig
exit /b 0


:: Action: Uninstall
:Action_Uninstall
powershell -NoProfile -Command "Stop-Service -Name '%RESOLVED_SERVICE%' -ErrorAction SilentlyContinue"
if exist "!DEST_FILE!" (
    del /f /q "!DEST_FILE!"
    echo %G%[+] Binary deleted: !DEST_FILE!%N%
) else (
    echo %Y%[^^!] Binary not found: !DEST_FILE!%N%
)
exit /b 0


:: Action: Run
:Action_Run
call :SelectAndRunConfig
exit /b 0


:: Action: Service Install
:Action_ServiceInstall
if "!IS_ADMIN!"=="0" (
    echo %R%[^^!] ERROR: Administration privileges are required to manage services.%N%
    exit /b 1
)
if not "!IMPORT_CONFIG!"=="" call :ImportConfigHelper
powershell -NoProfile -Command "Stop-Service -Name '%RESOLVED_SERVICE%' -ErrorAction SilentlyContinue"
powershell -NoProfile -Command "$service = Get-CimInstance -ClassName Win32_Service -Filter \"Name='%RESOLVED_SERVICE%'\" -ErrorAction SilentlyContinue; if ($service) { $service | Remove-CimInstance }"
Start-Sleep -Seconds 2
powershell -NoProfile -Command "New-Service -Name '%RESOLVED_SERVICE%' -BinaryPathName '\"!DEST_FILE!\" -c \"!CONFIG_FILE!\" run' -StartupType Automatic -DisplayName 'sing-box extended' -ErrorAction Stop | Out-Null"
if %ERRORLEVEL% neq 0 (
    echo %R%[^^!] ERROR: Failed to create Windows Service.%N%
    exit /b 1
)
echo %G%[+] Windows Service created: %RESOLVED_SERVICE%%N%
exit /b 0


:: Action: Service Remove
:Action_ServiceRemove
if "!IS_ADMIN!"=="0" (
    echo %R%[^^!] ERROR: Administration privileges are required to manage services.%N%
    exit /b 1
)
powershell -NoProfile -Command "Stop-Service -Name '%RESOLVED_SERVICE%' -ErrorAction SilentlyContinue"
powershell -NoProfile -Command "$service = Get-CimInstance -ClassName Win32_Service -Filter \"Name='%RESOLVED_SERVICE%'\" -ErrorAction SilentlyContinue; if ($service) { $service | Remove-CimInstance -ErrorAction Stop; Write-Output '1' } else { Write-Output '0' }" > "%TEMP%\svc_rem.txt"
set /p svc_removed=<"%TEMP%\svc_rem.txt"
del /f /q "%TEMP%\svc_rem.txt"

if "!svc_removed!"=="1" (
    echo %G%[+] Windows Service removed: %RESOLVED_SERVICE%%N%
) else (
    echo %Y%[^^!] Service not found: %RESOLVED_SERVICE%%N%
)
exit /b 0


:: Helper: Import Config
:ImportConfigHelper
if "!IMPORT_CONFIG!"=="" exit /b 0
for %%i in ("!IMPORT_CONFIG!") do set "abs_import=%%~fi"
if not exist "!abs_import!" (
    echo %R%[^^!] ERROR: Configuration file for import not found: !abs_import!%N%
    exit /b 1
)
echo %C%[*] Importing config: %Y%!abs_import!%N%
copy /y "!abs_import!" "!CONFIG_FILE!" >nul
if exist "!DEST_FILE!" (
    echo %C%[*] Checking configuration...%N%
    "!DEST_FILE!" -c "!CONFIG_FILE!" check
    if %ERRORLEVEL% neq 0 (
        echo %R%[^^!] ERROR: Configuration check failed.%N%
        exit /b 1
    )
    echo %G%[+] Configuration is valid.%N%
)
exit /b 0


:: Helper: Select and Run Config
:SelectAndRunConfig
if not exist "!DEST_FILE!" (
    echo %R%[^^!] ERROR: Binary not found: !DEST_FILE!%N%
    exit /b 1
)

:: Stop service if running to prevent port conflicts
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "$s = Get-Service -Name '%RESOLVED_SERVICE%' -ErrorAction SilentlyContinue; $s.Status"`) do set "svc_status=%%i"
if /i "!svc_status!"=="Running" (
    echo %Y%[^^!] Service %RESOLVED_SERVICE% is already running. Manual run might cause port conflicts.%N%
    set /p "stop_svc_choice=%C%[?] Stop service before manual run? [y/N]: %N%"
    if /i "!stop_svc_choice!"=="y" (
        powershell -NoProfile -Command "Stop-Service -Name '%RESOLVED_SERVICE%' -ErrorAction SilentlyContinue"
    )
)

if not "!IMPORT_CONFIG!"=="" (
    call :ImportConfigHelper
    set "RUN_CONF=!CONFIG_FILE!"
    goto do_run
)

echo.
echo %C%[*] Select configuration to run:%N%
echo   %Y%1%N%) Specify path to an existing configuration file
echo   %Y%2%N%) Create a new configuration file (default_config.json)
echo   %Y%0%N%) Cancel running sing-box-extended
echo.

:run_config_prompt
set "r_choice="
set /p "r_choice=%C%[?] Choose option (0-2): %N%"
if "!r_choice!"=="0" (
    echo %G%[*] Start cancelled.%N%
    exit /b 0
)
if "!r_choice!"=="1" (
    set /p "user_conf_path=%C%[?] Specify full path to config.json: %N%"
    for %%i in ("!user_conf_path!") do set "RUN_CONF=%%~fi"
    if not exist "!RUN_CONF!" (
        echo %R%[^^!] ERROR: Configuration file not found: !RUN_CONF!%N%
        exit /b 1
    )
    goto do_run
)
if "!r_choice!"=="2" (
    set "RUN_CONF=!DEST_DIR!\default_config.json"
    if not exist "!RUN_CONF!" (
        :: Write default json contents
        (
        echo {
        echo   "log": {
        echo     "level": "info",
        echo     "timestamp": true
        echo   },
        echo   "inbounds": [
        echo     {
        echo       "type": "mixed",
        echo       "tag": "mixed-in",
        echo       "listen": "127.0.0.1",
        echo       "listen_port": 7890,
        echo       "set_system_proxy": false
        echo     }
        echo   ],
        echo   "outbounds": [
        echo     {
        echo       "type": "direct",
        echo       "tag": "direct"
        echo     }
        echo   ],
        echo   "route": {
        echo     "final": "direct"
        echo   }
        echo }
        ) > "!RUN_CONF!"
        echo %G%[+] Config created: %Y%!RUN_CONF!%N%
    ) else (
        echo %Y%[^^!] File already exists: !RUN_CONF!%N%
    )

    :: Open JSON Editor
    echo %C%[*] Opening config in default editor...%N%
    echo %Y%[^^!] Save the file and close the editor to continue.%N%
    start /wait "" "!RUN_CONF!"
    goto do_run
)

:do_run
:: Test config
echo %C%[*] Checking configuration...%N%
"!DEST_FILE!" -c "!RUN_CONF!" check
if %ERRORLEVEL% neq 0 (
    echo %R%[^^!] ERROR: Configuration check failed.%N%
    exit /b 1
)
echo %G%[+] Configuration is valid.%N%

echo %C%[*] Starting sing-box extended...%N%
echo %Y%[^^!] Press Ctrl+C to stop.%N%
"!DEST_FILE!" -c "!RUN_CONF!" run
exit /b 0
