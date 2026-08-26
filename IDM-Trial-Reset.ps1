<#
.SYNOPSIS
    IDM Trial Reset — GUI version that aggressively deletes
    {07999AC3-058B-40BF-984F-69EB1E554CA7} from ALL registry hives.
    No auto-reset, no clutter. With Logs & Web links.
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

$form = New-Object System.Windows.Forms.Form
$form.Text = 'IDM Trial Reset'
$form.ClientSize = New-Object System.Drawing.Size(460, 240)
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
$lblSub.Text = 'Deletes {07999AC3-058B-40BF-984F-69EB1E554CA7} from ALL registry locations.'
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$lblSub.SetBounds(22, 55, 420, 20)
$form.Controls.Add($lblSub)

# Status label — dengan AutoSize = false dan fixed width supaya wrap
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 90, 158)
$lblStatus.SetBounds(22, 145, 420, 50)
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
# Log file path
# ---------------------------------------------------------------------------
$script:LogFile = Join-Path $env:TEMP 'idm-trial-reset.log'

# ---------------------------------------------------------------------------
# Core Logic: Aggressively Delete the Primary CLSID
# ---------------------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$stamp  $Message" | Out-File -LiteralPath $script:LogFile -Append -Encoding utf8
}

function Stop-IDM {
    foreach ($proc in 'IDMan', 'IEMonitor', 'IDMIntegrator64', 'IDMGrHlp') {
        Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Kill(); Write-Log "Stopped process: $($_.ProcessName)" } catch { Write-Log "Failed to kill $proc" }
        }
    }
    Start-Sleep -Milliseconds 300
}

function Delete-PrimaryClsid {
    $target = '{07999AC3-058B-40BF-984F-69EB1E554CA7}'
    Write-Log "===== STARTING AGGRESSIVE DELETE FOR $target ====="

    $roots = @(
        'HKCU:\Software\Classes\CLSID',
        'HKCU:\Software\Classes\Wow6432Node\CLSID',
        'HKLM:\Software\Classes\CLSID',
        'HKLM:\Software\WOW6432Node\Classes\CLSID'
    )

    $sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $hkuPaths = @(
        "HKU:\$sid\Software\Classes\CLSID\$target",
        "HKU:\$sid\Software\Classes\Wow6432Node\CLSID\$target",
        "HKU:\$sid_Classes\CLSID\$target",
        "HKU:\$sid_Classes\WOW6432Node\CLSID\$target"
    )

    $allPaths = $roots + $hkuPaths

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
    foreach ($p in $allPaths) {
        if (Test-Path -LiteralPath $p) {
            try {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
                $deletedCount++
                Write-Log "[✓] Deleted: $p"
            } catch {
                Write-Log "[!] Failed to delete $p : $_"
                try {
                    $hive, $sub = $p -split ':\\', 2
                    $regHive = switch ($hive) {
                        'HKCU' { [Microsoft.Win32.Registry]::CurrentUser }
                        'HKLM' { [Microsoft.Win32.Registry]::LocalMachine }
                        'HKU'  { [Microsoft.Win32.Registry]::Users }
                    }
                    $key = $regHive.OpenSubKey($sub, $true)
                    if ($key) {
                        $acl = $key.GetAccessControl()
                        $acl.SetOwner([System.Security.Principal.WindowsIdentity]::GetCurrent().User)
                        $key.SetAccessControl($acl)
                        $key.Close()
                        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
                        $deletedCount++
                        Write-Log "[✓] Deleted (with ownership): $p"
                    }
                } catch {
                    Write-Log "[✗] Still failed: $p"
                }
            }
        } else {
            Write-Log "[i] Not found: $p"
        }
    }

    # Wipe trial values
    $valuePaths = @(
        'HKCU:\Software\DownloadManager',
        'HKLM:\Software\Internet Download Manager',
        'HKLM:\Software\Wow6432Node\Internet Download Manager',
        "HKU:\$sid\Software\DownloadManager"
    )
    $values = @('Serial','FName','LName','Email','LstCheck','checkdt','tvqals','scansk','Trial','TrialDate','LastCheck')
    foreach ($vp in $valuePaths) {
        if (Test-Path -LiteralPath $vp) {
            foreach ($v in $values) {
                try {
                    Remove-ItemProperty -LiteralPath $vp -Name $v -ErrorAction SilentlyContinue
                    Write-Log "[✓] Removed value: $vp\$v"
                } catch {
                    Write-Log "[i] Value not found: $vp\$v"
                }
            }
        }
    }

    Write-Log "===== DELETE COMPLETE — $deletedCount keys deleted ====="
    return $deletedCount
}

# ---------------------------------------------------------------------------
# Button Click Event
# ---------------------------------------------------------------------------
$btnReset.Add_Click({
    $btnReset.Enabled = $false
    $btnReset.Text = 'Deleting...'
    $lblStatus.Text = 'Killing IDM processes...'
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 90, 158)
    Write-Log "User clicked Reset button."
    [System.Windows.Forms.Application]::DoEvents()

    Stop-IDM

    $lblStatus.Text = 'Deleting {07999AC3-058B-40BF-984F-69EB1E554CA7} from ALL hives...'
    [System.Windows.Forms.Application]::DoEvents()

    $count = Delete-PrimaryClsid

    $lblStatus.Text = "✓ Done! Deleted $count registry key(s). IDM trial reset!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(16, 124, 16)

    Write-Log "Reset completed — $count keys deleted."

    [System.Windows.Forms.MessageBox]::Show(
        "Key {07999AC3-058B-40BF-984F-69EB1E554CA7} has been deleted from ALL registry locations.`n`nIDM will now show a fresh 30-day trial.`n`nKeys deleted: $count",
        'IDM Trial Reset',
        'OK',
        'Information'
    )

    $btnReset.Text = 'Reset IDM Trial Now'
    $btnReset.Enabled = $true
})

# ---------------------------------------------------------------------------
# Link Events
# ---------------------------------------------lnkWeb------------------------------
$lnkLogs.Add_LinkClicked({
    if (Test-Path -LiteralPath $script:LogFile) {
        Start-Process notepad.exe $script:LogFile
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            'Log file not found yet. Run a reset first to generate it.',
            'Logs',
            'OK',
            'Information'
        )
    }
})

$lnkWeb.Add_LinkClicked({
    Start-Process 'https://naifmuazzam.dev'
})

# ---------------------------------------------------------------------------
# Run the GUI
# ---------------------------------------------------------------------------
Write-Log "--- IDM Trial Reset GUI started ---"
[System.Windows.Forms.Application]::Run($form)