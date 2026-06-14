[🇷🇺 Русский](../README.md) | [🇺🇸 English](README.md)

# 📦 sing-box-extended Installer for Windows

An interactive installer, updater, and runner manager of [sing-box-extended](https://github.com/shtorm-7/sing-box-extended) for the Windows operating system family.

This script is written in PowerShell, inspired by [OpenWRT-sing-box-extended](https://github.com/EikeiDev/OpenWRT-sing-box-extended), but tailored specifically for Windows environments.

## ✨ Features

- 🔄 **Interactive Installation and Updates** — fetches the list of the 5 latest stable releases from GitHub and prompts the user to select their desired version.
- 🧠 **Current Version Detection** — displays both the currently installed version and the selected version before proceeding.
- 🏗 **Architecture Detection** — automatically detects the host architecture, supporting `amd64`, `arm64`, and `386`.
- 📦 **Automated Release Download** — downloads the corresponding `windows-*.zip` archive directly from GitHub Releases.
- 🧩 **Service Integration** — detects and restarts existing service names (`podkop`, `sing-box-extended`, or `sing-box`).
- 🧯 **Backup and Rollback** — creates a backup of `sing-box.exe` before replacement; attempts rollback/restoration if the installation fails.
- 📥 **Config Import** — imports an existing `config.json` configuration file via the `-ImportConfig` parameter.
- 🚀 **Manual Run Post-Installation** — offers to start `sing-box-extended` directly after installation or manually via the `Run` action.
- 🧾 **Post-Install Configuration Management**:
  - Specify the path to an existing configuration file.
  - Create a new configuration file in the installation directory (opens in your default JSON editor).

## 🚀 Usage

The commands below assume you are already running them within a PowerShell prompt.

### Standard Interactive Installation

```powershell
.\en\install-sing-box-extended-win.ps1
```

### Installation to a Specific Path

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -DestFile "C:\Program Files\sing-box-extended\sing-box.exe"
```

### PATH Variable Management

By default, the installation directory is added to the User `PATH` variable.

To add to the Machine `PATH` instead of the User `PATH`:

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -AddToMachinePath
```

To disable modifying the `PATH` entirely:

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -NoAddToPath
```

## ⚙️ Actions (`-Action`)

| Action           | Purpose                                           |
|------------------|---------------------------------------------------|
| `Install`        | Interactive installation of the selected version  |
| `Update`         | Interactive update to the selected version        |
| `Uninstall`      | Deletes the installed `sing-box.exe`              |
| `Run`            | Runs the installed `sing-box.exe` with a config   |
| `ServiceInstall` | Creates or recreates the Windows Service          |
| `ServiceRemove`  | Deletes the Windows Service                       |

### Run with an Existing Configuration File

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -Action Run `
  -ConfigFile "C:\Program Files\sing-box-extended\config.json"
```

### Run with Configuration Import

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -Action Run `
  -ImportConfig "C:\Users\User\Downloads\config.json"
```

### Uninstall the Binary

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -Action Uninstall
```

## 🪟 Windows Service

> Managing Windows Services (creating/removing) requires launching PowerShell as an Administrator.

### Create Service as a Separate Action

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -Action ServiceInstall `
  -ServiceName sing-box-extended `
  -ConfigFile "C:\Program Files\sing-box-extended\config.json"
```

### Install and Create Service in a Single Command

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -Action Install `
  -CreateService `
  -ConfigFile "C:\Program Files\sing-box-extended\config.json"
```

The service will be configured with a start command resembling:

```powershell
"C:\Program Files\sing-box-extended\sing-box.exe" -c "C:\Program Files\sing-box-extended\config.json" run
```

### Remove the Service

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -Action ServiceRemove `
  -ServiceName sing-box-extended
```

## 🖥 Supported Windows Architectures

| Architecture | Platform Context                                                             |
|--------------|------------------------------------------------------------------------------|
| `amd64`      | Most modern PCs, laptops, servers, and standard Windows virtual machines     |
| `arm64`      | Windows on ARM, ARM devices, and specific virtualized environments           |
| `386`        | Legacy 32-bit Windows systems                                                |

The architecture is detected automatically. You can explicitly override it using:

```powershell
.\en\install-sing-box-extended-win.ps1 `
  -ArchSuffix amd64
```

## 📋 Sample Output

```text
[*] Retrieving latest versions...

[*] Available stable versions for installation:
  1) v1.13.12-extended-2.4.1
  2) v1.13.12-extended-2.4.0
  3) v1.13.12-extended-2.3.2
  4) v1.13.9-extended-2.3.1
  5) v1.13.8-extended-2.3.0
  0) Cancel

[?] Choose version (0-5):
```

## 📁 Configuration File Locations

If you use `-ImportConfig` and `-ConfigFile` is omitted, the configuration is copied here:

```text
<install_directory>\config.json
```

If you select to create a new configuration file during startup, it is initialized as:

```text
<install_directory>\default_config.json
```

The execution command always resolves to an absolute path:

```powershell
sing-box.exe -c "C:\Program Files\sing-box-extended\default_config.json" run
```

## ⚙️ Prerequisites

- Windows 10 / Windows 11 / Windows Server
- PowerShell 5.1 or newer
- Internet access to GitHub API and GitHub Releases
- Elevated permissions (Run as Administrator) are required for installing to `C:\Program Files`, creating/removing Windows Services, and utilizing the `-AddToMachinePath` option.

## 📄 Credits

- [OpenWRT-sing-box-extended](https://github.com/EikeiDev/OpenWRT-sing-box-extended) ([@EikeiDev](https://github.com/EikeiDev))
- [sing-box-extended](https://github.com/shtorm-7/sing-box-extended) ([@shtorm-7](https://github.com/shtorm-7))
