# IDM Trial Reset

A lightweight PowerShell tool that resets the Internet Download Manager (IDM) trial period by aggressively deleting the primary trial registry key — giving you a fresh 30-day trial each time.

> If you find this useful, consider [buying a license](https://www.internetdownloadmanager.com/) to support the developer.

---

## Features

- **One‑click trial reset** — deletes `{07999AC3-058B-40BF-984F-69EB1E554CA7}` from ALL registry hives (HKCU, HKLM, HKU — all user SIDs)
- **Aggressive deletion** — scans every possible registry location, takes ownership if needed, and wipes the key completely
- **Trial value wipe** — removes `Serial`, `FName`, `LName`, `Email`, `LstCheck`, `checkdt`, `tvqals`, `scansk`, `Trial`, `TrialDate`, `LastCheck`, and more
- **No dependencies** — pure PowerShell, no bundled executables, no temp `.reg` files
- **Clean GUI** — simple WinForms interface with status updates and log viewer
- **Admin‑aware** — auto‑elevates to Administrator via UAC
- **Built‑in logging** — all actions logged to `%TEMP%\idm-trial-reset.log`

---

## Quick Start

1. Download or clone this repository
2. Double‑click **`IDM-Trial-Reset.bat`**
3. Click **Yes** on the UAC prompt
4. Click **Reset the IDM Trial Now**
5. Done — IDM now has a fresh 30‑day trial

---

## Files

| File | Description |
|------|-------------|
| `IDM-Trial-Reset.ps1` | Main PowerShell script (GUI + logic) |
| `IDM-Trial-Reset.bat` | Double‑click launcher (calls the script) |
| `IDM.ico` | Window icon (optional) |

---

## GUI Overview

| Element | Function |
|---------|----------|
| **Reset the IDM Trial Now** | Main button — kills IDM, deletes the registry key, wipes trial values |
| **Web** (top‑right) | Opens `https://naifmuazzam.dev` — your developer website |
| **Logs** (top‑right) | Opens the log file (`%TEMP%\idm-trial-reset.log`) in Notepad |
| **Status label** | Shows real‑time progress (wraps automatically if text is long) |

---

## How It Works

1. **Kills IDM processes** — `IDMan.exe`, `IEMonitor.exe`, `IDMIntegrator64.exe`, `IDMGrHlp.exe` — so IDM can't rewrite the registry while we work.
2. **Scans ALL registry locations** for the target CLSID:
   - `HKCU\Software\Classes\CLSID\{07999AC3-058B-40BF-984F-69EB1E554CA7}`
   - `HKCU\Software\Classes\Wow6432Node\CLSID\{07999AC3-058B-40BF-984F-69EB1E554CA7}`
   - `HKLM\Software\Classes\CLSID\{07999AC3-058B-40BF-984F-69EB1E554CA7}`
   - `HKLM\Software\WOW6432Node\Classes\CLSID\{07999AC3-058B-40BF-984F-69EB1E554CA7}`
   - All `HKU\<SID>\...` variants (current user + every other user SID)
3. **Takes ownership** if access is denied — uses native .NET `RegistrySecurity` to grant FullControl.
4. **Deletes the key** recursively from every location found.
5. **Wipes trial values** from `HKCU\Software\DownloadManager`, `HKLM\Software\Internet Download Manager`, and `HKU\<SID>\Software\DownloadManager`.
6. **Logs everything** — each deletion, failure, and permission change is written to the log file.

---

## Command Line

```powershell
# Run with GUI (default)
.\IDM-Trial-Reset.ps1

# Run silently (for automated/scheduled tasks)
powershell -NoProfile -ExecutionPolicy Bypass -File .\IDM-Trial-Reset.ps1 -Silent