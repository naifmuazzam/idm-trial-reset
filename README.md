# IDM Trial Reset

A lightweight PowerShell tool that resets the Internet Download Manager (IDM) trial period, giving you a fresh 30-day trial each time.

> If you find this useful, consider [buying a license](https://www.internetdownloadmanager.com/) to support the developer.

## Features

- **One-click trial reset** — delete all trial data so IDM starts a fresh 30-day trial
- **Auto-reset** — automatically reset every 15 days via Windows Task Scheduler
- **No dependencies** — pure PowerShell, no bundled executables
- **No temp files** — writes registry directly, no `.reg` files
- **Responsive GUI** — WinForms interface that stays responsive during reset
- **Admin-aware** — auto-elevates to admin when needed

## Quick Start

1. Download or clone this repository
2. Double-click **`IDM-Trial-Reset.bat`**
3. Click **Yes** on the UAC prompt
4. Click **Reset the IDM trial now**
5. Done — IDM has a fresh 30-day trial

> **Tip:** Enable *Automatically reset every 15 days* so the trial never expires.

## How It Works

1. Kills IDM processes (`IDMan.exe`, `IEMonitor.exe`, etc.) to prevent registry conflicts
2. Deletes all IDM CLSID keys from the registry (trial state)
3. Removes trial-tracking values (`scansk`, `tvqals`, `LstCheck`, etc.)
4. Locks the CLSID keys with Deny FullControl to prevent IDM from re-registering

## Files

| File | Description |
|---|---|
| `IDM-Trial-Reset.ps1` | Main script (GUI + logic) |
| `IDM-Trial-Reset.bat` | Double-click launcher |
| `IDM.ico` | Window icon |

## Command Line

```powershell
# Run with GUI (default)
.\IDM-Trial-Reset.ps1

# Run silently (for auto-reset / scheduled tasks)
powershell -NoProfile -ExecutionPolicy Bypass -File .\IDM-Trial-Reset.ps1 -Silent
```

## Requirements

- Windows 10 or later
- PowerShell 5.1+ (preinstalled on Windows 10/11)
- Administrator rights (auto-elevated via UAC)

## Troubleshooting

- Logs are written to `%TEMP%\idm-trial-reset.log`
- Click **Open log** in the GUI to view the log file
- If the reset fails, check that IDM is fully closed (including tray icon)

## License

MIT
