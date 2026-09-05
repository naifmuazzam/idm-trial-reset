<#
.SYNOPSIS
    IDM Trial Reset — Aggressively wipes ALL trial state from registry,
    files, scheduled tasks, services, and Explorer shell cache.
.DESCRIPTION
    Deletes {07999AC3-058B-40BF-984F-69EB1E554CA7} from ALL registry hives,
    cleans IDM installation trial files, removes scheduled tasks,
    kills + restarts Explorer, and verifies no residual CLSID remains.
#>

# Self-elevate to Administrator
$currentId = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentId)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") -Verb RunAs
    return
}

# ---------------------------------------------------------------------------
# GUI Setup
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# SHChangeNotify for shell cache refresh
Add-Type -MemberDefinition '[DllImport("shell32.dll", SetLastError = true)] public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);' -Name 'SHChange' -Namespace 'Win32' -PassThru | Out-Null

$form = New-Object System.Windows.Forms.Form
$form.Text = 'IDM Trial Reset'
$form.ClientSize = New-Object System.Drawing.Size(460, 280)
$form.StartPosition = 'CenterScreen'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.FormBorderStyle = 'FixedDialog'
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 242, 245)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# --- Top-right links ---
$lnkLogs = New-Object System.Windows.Forms.LinkLabel
$lnkLogs.Text = '➤ Logs'
$lnkLogs.SetBounds(370, 12, 70, 20)
$lnkLogs.LinkColor = [System.Drawing.Color]::FromArgb(0, 90, 158)
$lnkLogs.ActiveLinkColor = [System.Drawing.Color]::FromArgb(0, 60, 120)
$lnkLogs.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($lnkLogs)

$lnkWeb = New-Object System.Windows.Forms.LinkLabel
$lnkWeb.Text = '➤ Web'
$lnkWeb.SetBounds(310, 12, 60, 20)
$lnkWeb.LinkColor = [System.Drawing.Color]::FromArgb(0, 90, 158)
$lnkWeb.ActiveLinkColor = [System.Drawing.Color]::FromArgb(0, 60, 120)
$lnkWeb.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($lnkWeb)

# Title
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'IDM Trial Reset'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$lblTitle.SetBounds(20, 20, 420, 30)
$form.Controls.Add($lblTitle)

# Subtitle
$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = 'Aggressively wipes ALL trial state from registry + files.'
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$lblSub.SetBounds(22, 55, 420, 20)
$form.Controls.Add($lblSub)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.SetBounds(22, 180, 420, 18)
$progressBar.Style = 'Continuous'
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$form.Controls.Add($progressBar)

# Status label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 90, 158)
$lblStatus.SetBounds(22, 205, 420, 60)
$lblStatus.AutoSize = $false
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)
$form.Controls.Add($lblStatus)

# Reset Button
$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = 'Reset IDM Trial Now'
$btnReset.SetBounds(110, 85, 240, 45)
$btnReset.FlatStyle = 'Flat'
$btnReset.FlatAppearance.BorderSize = 0
$btnReset.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnReset.ForeColor = [System.Drawing.Color]::White
$btnReset.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$btnReset.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnReset.Add_MouseEnter({ $this.BackColor = [System.Drawing.Color]::FromArgb(16, 110, 190) })
$btnReset.Add_MouseLeave({ $this.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215) })
$form.Controls.Add($btnReset)

# ---------------------------------------------------------------------------
# Log file
# ---------------------------------------------------------------------------
$script:LogFile = Join-Path $env:TEMP 'idm-trial-reset.log'

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$stamp  $Message" | Out-File -LiteralPath $script:LogFile -Append -Encoding utf8
}

function Update-UI {
    param([string]$text, [int]$percent)
    $lblStatus.Text = $text
    $progressBar.Value = [Math]::Min($percent, 100)
    [System.Windows.Forms.Application]::DoEvents()
}

# ---------------------------------------------------------------------------
# STEP 1: Kill all IDM processes
# ---------------------------------------------------------------------------
function Stop-IDM {
    Update-UI 'Step 1/5 — Killing IDM processes...' 5
    $procs = @('IDMan', 'IEMonitor', 'IDMIntegrator64', 'IDMGrHlp', 'IDMGrHlp64')
    foreach ($proc in $procs) {
        Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $_.Kill()
                Write-Log "Killed: $($_.ProcessName) (PID $($_.Id))"
            } catch {
                Write-Log "Failed to kill $proc — $_"
            }
        }
    }
    Start-Sleep -Milliseconds 500
}

# ---------------------------------------------------------------------------
# STEP 2: Delete CLSID from ALL registry locations
# ---------------------------------------------------------------------------
function Delete-PrimaryClsid {
    Update-UI 'Step 2/5 — Deleting CLSID from ALL registry hives...' 20

    $target = '{07999AC3-058B-40BF-984F-69EB1E554CA7}'
    Write-Log "===== AGGRESSIVE DELETE: $target ====="

    # --- All possible CLSID root paths ---
    $roots = @(
        'HKCU:\Software\Classes\CLSID',
        'HKCU:\Software\Classes\Wow6432Node\CLSID',
        'HKLM:\Software\Classes\CLSID',
        'HKLM:\Software\WOW6432Node\Classes\CLSID',
        'HKCR:\CLSID',
        'HKCR:\Wow6432Node\CLSID'
    )

    # --- HKU paths for current user ---
    $sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $hkuPaths = @(
        "HKU:\$sid\Software\Classes\CLSID\$target",
        "HKU:\$sid\Software\Classes\Wow6432Node\CLSID\$target",
        "HKU:\$sid_Classes\CLSID\$target",
        "HKU:\$sid_Classes\WOW6432Node\CLSID\$target"
    )

    $allPaths = @()

    # Build paths from root hives
    foreach ($root in $roots) {
        $allPaths += "$root\$target"
    }
    $allPaths += $hkuPaths

    # --- All other user SIDs loaded in HKU ---
    $allUserSids = Get-ChildItem 'HKU:\' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'S-1-5-21-' }
    foreach ($u in $allUserSids) {
        $uSid = Split-Path -Leaf $u.Name
        $allPaths += @(
            "HKU:\$uSid\Software\Classes\CLSID\$target",
            "HKU:\$uSid\Software\Classes\Wow6432Node\CLSID\$target",
            "HKU:\$uSid_Classes\CLSID\$target",
            "HKU:\$uSid_Classes\WOW6432Node\CLSID\$target"
        )
    }

    $deletedCount = 0
    $total = $allPaths.Count
    $i = 0

    foreach ($p in $allPaths) {
        $i++
        $pct = 20 + [int](40 * ($i / $total))
        Update-UI "Step 2/5 — Scanning registry ($i/$total)..." $pct

        if (Test-Path -LiteralPath $p) {
            try {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
                $deletedCount++
                Write-Log "[OK] Deleted: $p"
            } catch {
                Write-Log "[FAIL] $p — $_"
                # Retry with ownership takeover
                try {
                    $hive, $sub = $p -split ':\\', 2
                    $regHive = switch ($hive) {
                        'HKCU' { [Microsoft.Win32.Registry]::CurrentUser }
                        'HKLM' { [Microsoft.Win32.Registry]::LocalMachine }
                        'HKU'  { [Microsoft.Win32.Registry]::Users }
                        'HKCR' { [Microsoft.Win32.Registry]::ClassesRoot }
                    }
                    $key = $regHive.OpenSubKey($sub, $true)
                    if ($key) {
                        $acl = $key.GetAccessControl()
                        $acl.SetOwner([System.Security.Principal.WindowsIdentity]::GetCurrent().User)
                        $key.SetAccessControl($acl)
                        $key.Close()
                        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
                        $deletedCount++
                        Write-Log "[OK] Deleted (ownership): $p"
                    }
                } catch {
                    Write-Log "[STILL FAIL] $p"
                }
            }
        }
    }

    return $deletedCount
}

# ---------------------------------------------------------------------------
# STEP 2b: Clear trial values from IDM registry keys
# ---------------------------------------------------------------------------
function Clear-TrialValues {
    Update-UI 'Step 2/5 — Clearing trial values...' 55

    $sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $valuePaths = @(
        'HKCU:\Software\DownloadManager',
        'HKCU:\Software\Internet Download Manager',
        'HKLM:\Software\Internet Download Manager',
        'HKLM:\Software\Wow6432Node\Internet Download Manager',
        "HKU:\$sid\Software\DownloadManager",
        "HKU:\$sid\Software\Internet Download Manager",
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Internet Download Manager',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Internet Download Manager',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\IDMan.exe'
    )

    $values = @(
        'Serial', 'FName', 'LName', 'Email', 'LstCheck', 'checkdt',
        'tvqals', 'scansk', 'Trial', 'TrialDate', 'LastCheck',
        'ExpiryDate', 'RegisteredTo', 'SerialNumber', 'ProductKey',
        'InstallDate', 'InstallLocation', 'LicenseKey'
    )

    $cleared = 0
    foreach ($vp in $valuePaths) {
        if (Test-Path -LiteralPath $vp) {
            foreach ($v in $values) {
                try {
                    Remove-ItemProperty -LiteralPath $vp -Name $v -ErrorAction Stop
                    Write-Log "[OK] Removed: $vp\$v"
                    $cleared++
                } catch {
                    # Value doesn't exist — skip silently
                }
            }
        }
    }

    # Also remove the entire CLSID subkey under DownloadManager if it references the target
    $target = '{07999AC3-058B-40BF-984F-69EB1E554CA7}'
    $dmPaths = @(
        'HKCU:\Software\DownloadManager',
        'HKCU:\Software\Internet Download Manager'
    )
    foreach ($dp in $dmPaths) {
        if (Test-Path -LiteralPath "$dp\Lookup") {
            try {
                Remove-Item -LiteralPath "$dp\Lookup" -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "[OK] Removed lookup cache: $dp\Lookup"
            } catch {}
        }
    }

    Write-Log "Cleared $cleared trial values total."
    return $cleared
}

# ---------------------------------------------------------------------------
# STEP 3: Clean IDM installation folder trial files
# ---------------------------------------------------------------------------
function Clean-InstallFiles {
    Update-UI 'Step 3/5 — Cleaning IDM installation folder...' 65

    $idmDirs = @(
        "${env:ProgramFiles}\Internet Download Manager",
        "${env:ProgramFiles(x86)}\Internet Download Manager"
    )

    $trialPatterns = @(
        '*.tmp', '*.log', '*.dat', 'idm_trial*', 'register*',
        'trial*', '*.bak', 'DefaultSet*', 'Faces*', '*.gid',
        'IDMGrHlp.dat', '*.part'
    )

    $cleaned = 0
    foreach ($dir in $idmDirs) {
        if (Test-Path $dir) {
            Write-Log "Scanning: $dir"
            foreach ($pattern in $trialPatterns) {
                Get-ChildItem -Path $dir -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        Write-Log "[OK] Deleted file: $($_.FullName)"
                        $cleaned++
                    } catch {
                        Write-Log "[SKIP] Locked: $($_.FullName)"
                    }
                }
            }
        }
    }

    # Also check %APPDATA% and %LOCALAPPDATA% for IDM data
    $appDataPaths = @(
        "$env:APPDATA\IDM",
        "$env:LOCALAPPDATA\IDM",
        "$env:APPDATA\Internet Download Manager",
        "$env:LOCALAPPDATA\Internet Download Manager"
    )
    foreach ($ad in $appDataPaths) {
        if (Test-Path $ad) {
            Write-Log "Scanning AppData: $ad"
            Get-ChildItem -Path $ad -Filter '*.dat' -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    Write-Log "[OK] Deleted AppData file: $($_.FullName)"
                    $cleaned++
                } catch {}
            }
        }
    }

    Write-Log "Cleaned $cleaned files."
    return $cleaned
}

# ---------------------------------------------------------------------------
# STEP 4: Remove scheduled tasks + restart services
# ---------------------------------------------------------------------------
function Clean-TasksAndServices {
    Update-UI 'Step 4/5 — Cleaning tasks & services...' 80

    $removed = 0

    # Remove IDM scheduled tasks
    try {
        $tasks = schtasks /query /fo csv 2>$null | Select-String -Pattern 'IDM' -CaseSensitive:$false
        foreach ($line in $tasks) {
            $taskName = ($line.Line -split ',')[0].Trim('"')
            if ($taskName) {
                schtasks /delete /tn $taskName /f 2>$null
                Write-Log "[OK] Deleted task: $taskName"
                $removed++
            }
        }
    } catch {
        Write-Log "[i] Task cleanup skipped: $_"
    }

    # Restart IDMGrHlp service
    $svcNames = @('IDMGrHlp', 'IDMGrHlp64')
    foreach ($svc in $svcNames) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            try {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
                Write-Log "[OK] Stopped service: $svc"
                $removed++
            } catch {
                Write-Log "[i] Could not stop $svc"
            }
        }
    }

    Write-Log "Cleaned $removed tasks/services."
    return $removed
}

# ---------------------------------------------------------------------------
# STEP 5: Verify only — fast Test-Path, NO recurse, NO explorer kill
# ---------------------------------------------------------------------------
function Restart-ExplorerAndVerify {
    Update-UI 'Step 5/5 — Verifying...' 90

    # SHChangeNotify to refresh shell cache (no explorer restart needed)
    [Win32.SHChange]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
    Write-Log "SHChangeNotify fired."

    # Fast verify: direct Test-Path only — NO Get-ChildItem -Recurse
    # (Recurse over HKLM\Software\Classes = 1-2 min freeze, that was the bug)
    $target = '{07999AC3-058B-40BF-984F-69EB1E554CA7}'
    $checkPaths = @(
        "HKCU:\Software\Classes\CLSID\$target",
        "HKCU:\Software\Classes\Wow6432Node\CLSID\$target",
        "HKLM:\Software\Classes\CLSID\$target",
        "HKLM:\Software\WOW6432Node\Classes\CLSID\$target",
        "HKCR:\CLSID\$target",
        "HKCR:\Wow6432Node\CLSID\$target"
    )

    $residual = 0
    foreach ($p in $checkPaths) {
        [System.Windows.Forms.Application]::DoEvents()
        if (Test-Path -LiteralPath $p) {
            Write-Log "[WARNING] Residual found: $p"
            try {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
                Write-Log "[OK] Force-deleted residual: $p"
            } catch {
                Write-Log "[FAIL] Could not remove residual: $p"
                $residual++
            }
        }
    }

    return $residual
}

# ---------------------------------------------------------------------------
# Button Click — Full Reset Pipeline
# ---------------------------------------------------------------------------
$btnReset.Add_Click({
    $btnReset.Enabled = $false
    $btnReset.Text = 'Processing...'
    $progressBar.Value = 0
    Write-Log "===== USER CLICKED RESET ====="

    try {
        Stop-IDM
        $clsidDeleted = Delete-PrimaryClsid
        $valuesCleared = Clear-TrialValues
        $filesCleaned = Clean-InstallFiles
        $tasksCleaned = Clean-TasksAndServices
        $residualCount = Restart-ExplorerAndVerify

        Update-UI 'All done!' 100

        $summary = "Registry keys deleted: $clsidDeleted`nTrial values cleared: $valuesCleared`nFiles cleaned: $filesCleaned`nTasks/services: $tasksCleaned`nResiduals found after verify: $residualCount"

        Write-Log "===== RESET COMPLETE ====="
        Write-Log $summary

        $suffix = if ($residualCount -gt 0) { "`n`n⚠ Some residual keys remained — may need manual cleanup." } else { "`n`nIDM should now show a fresh 30-day trial." }

        [System.Windows.Forms.MessageBox]::Show(
            "$summary$suffix",
            'IDM Trial Reset — Complete',
            'OK',
            'Information'
        )
    } catch {
        Update-UI "Error: $_" 0
        Write-Log "[ERROR] $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Error during reset:`n`n$($_.Exception.Message)",
            'Error',
            'OK',
            'Error'
        )
    }

    $btnReset.Text = 'Reset IDM Trial Now'
    $btnReset.Enabled = $true
})

# ---------------------------------------------------------------------------
# Link Events
# ---------------------------------------------------------------------------
$lnkLogs.Add_LinkClicked({
    if (Test-Path -LiteralPath $script:LogFile) {
        Start-Process notepad.exe $script:LogFile
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            'Log file not found yet. Run a reset first.',
            'Logs', 'OK', 'Information'
        )
    }
})

$lnkWeb.Add_LinkClicked({
    Start-Process 'https://naifmuazzam.dev'
})

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
Write-Log "--- IDM Trial Reset GUI v2 started ---"
[System.Windows.Forms.Application]::Run($form)
