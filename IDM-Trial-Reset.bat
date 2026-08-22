@echo off
rem Launcher for the PowerShell IDM Trial Reset script.
rem Double-click this file - it will ask for admin rights via the script.

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%IDM-Trial-Reset.ps1" %*
