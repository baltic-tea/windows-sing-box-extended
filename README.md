# 📦 sing-box-extended Installer for Windows

Интерактивный установщик, обновлятор и менеджер запуска [sing-box-extended](https://github.com/shtorm-7/sing-box-extended) для семейства операционных систем Windows.

Скрипт написан на PowerShell по аналогии с [OpenWRT-sing-box-extended](https://github.com/EikeiDev/OpenWRT-sing-box-extended), но предназначен для Windows.

## ✨ Возможности

- 🔄 **Интерактивная установка и обновление** — получает список 5 последних стабильных релизов с GitHub и предлагает выбрать нужную версию.
- 🧠 **Проверка текущей версии** — показывает установленную и выбранную версию перед установкой.
- 🏗 **Определение архитектуры Windows** — поддерживаются `amd64`, `arm64`, `386`.
- 📦 **Автоматическая загрузка релиза** — скачивает подходящий `windows-*.zip` из GitHub Releases.
- 🧩 **Совместимость со службами** — умеет обнаруживать и перезапускать существующие службы `podkop`, `sing-box-extended` или `sing-box`.
- 🧯 **Backup и rollback** — перед заменой `sing-box.exe` создаётся backup; при ошибке установки выполняется попытка восстановления.
- 📥 **Импорт конфига** — можно передать готовый `config.json` через `-ImportConfig`.
- 🚀 **Ручной запуск после установки** — можно запустить `sing-box-extended` сразу после установки или отдельным действием `Run`.
- 🧾 **Работа с файлами конфигурации после установки**:
  - можно указать путь к существующему файлу конфигурации;
  - можно создать новый файл конфигурации в директории установки (открывается приложение для работы с JSON-файлами по умолчанию).

## 🚀 Использование

Команды ниже предполагают, что запуск выполняется уже из PowerShell.

### Обычная интерактивная установка

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1
```

### Установка по конкретному пути

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -DestFile "C:\Program Files\sing-box-extended\sing-box.exe"
```

### Управление добавлением в PATH

По умолчанию директория установки добавляется в User PATH.

Добавить в Machine PATH вместо User PATH:

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -AddToMachinePath
```

Отключить изменение PATH:

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -NoAddToPath
```

## ⚙️ Действия `-Action`

| Action           | Назначение                                      |
|------------------|-------------------------------------------------|
| `Install`        | Интерактивная установка выбранной версии        |
| `Update`         | Интерактивное обновление выбранной версии       |
| `Uninstall`      | Удаление установленного `sing-box.exe`          |
| `Run`            | Запуск установленного `sing-box.exe` с конфигом |
| `ServiceInstall` | Создание или пересоздание Windows Service       |
| `ServiceRemove`  | Удаление Windows Service                        |

### Запуск с существующим конфигом

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -Action Run `
  -ConfigFile "C:\Program Files\sing-box-extended\config.json"
```

### Запуск с импортом конфига

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -Action Run `
  -ImportConfig "C:\Users\User\Downloads\config.json"
```

### Удаление бинарника

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -Action Uninstall
```

## 🪟 Windows Service

> Для создания или удаления службы PowerShell нужно запускать от имени администратора.

### Создание службы отдельным действием

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -Action ServiceInstall `
  -ServiceName sing-box-extended `
  -ConfigFile "C:\Program Files\sing-box-extended\config.json"
```

### Установка и создание службы одним запуском

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -Action Install `
  -CreateService `
  -ConfigFile "C:\Program Files\sing-box-extended\config.json"
```

Служба создаётся с командой запуска вида:

```powershell
"C:\Program Files\sing-box-extended\sing-box.exe" -c "C:\Program Files\sing-box-extended\config.json" run
```

### Удаление службы

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -Action ServiceRemove `
  -ServiceName sing-box-extended
```

## 🖥 Поддерживаемые архитектуры Windows

| Архитектура | Платформы                                                                   |
|-------------|-----------------------------------------------------------------------------|
| `amd64`     | Большинство современных ПК, ноутбуков, серверов и виртуальных машин Windows |
| `arm64`     | Windows on ARM, ARM-устройства и некоторые виртуальные среды                |
| `386`       | Старые 32-битные Windows-системы                                            |

Архитектура определяется автоматически. При необходимости её можно задать вручную:

```powershell
.\install-sing-box-extended-windows-v4-clean.ps1 `
  -ArchSuffix amd64
```

## 📋 Пример вывода

```text
[*] Получаю список последних версий...

[*] Доступные стабильные версии для установки:
  1) v1.13.12-extended-2.1.7
  2) v1.13.11-extended-2.1.6
  3) v1.13.10-extended-2.1.5
  4) v1.13.9-extended-2.1.4
  5) v1.13.8-extended-2.1.3
  0) Отмена

[?] Выберите версию (0-5):
```

## 📁 Где хранится конфигурация

Если используется `-ImportConfig` и `-ConfigFile` не указан, конфиг копируется сюда:

```text
<директория установки>\config.json
```

Если пользователь выбирает создание нового конфига при запуске, создаётся:

```text
<директория установки>\default_config.json
```

При запуске всегда используется явный путь:

```powershell
sing-box.exe -c "C:\Program Files\sing-box-extended\default_config.json" run
```

## ⚙️ Требования

- Windows 10 / Windows 11 / Windows Server
- PowerShell 5.1 или новее
- Доступ в интернет к GitHub API и GitHub Releases
- Для установки в `C:\Program Files`, а также для создания/удаления Windows Service — запуск от имени администратора
- Для `-AddToMachinePath` также нужны права администратора

## 📄 Благодарности

- [OpenWRT-sing-box-extended](https://github.com/EikeiDev/OpenWRT-sing-box-extended) ([@EikeiDev](https://github.com/EikeiDev))
- [sing-box-extended](https://github.com/shtorm-7/sing-box-extended) ([@shtorm-7](https://github.com/shtorm-7))
