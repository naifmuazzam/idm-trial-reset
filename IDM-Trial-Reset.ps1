<#
.SYNOPSIS
    IDM Trial Reset — delete all trial data so IDM starts a fresh 30-day trial.
.DESCRIPTION
    Port of the original AutoIt "IDM Trial Reset" to pure PowerShell.
    - No AutoIt, no bundled SetACL.exe, no temp .reg files.
    - All registry ACL work is done with native .NET classes.
    - Kills IDM before touching the registry so it can't rewrite its licence.
.PARAMETER Silent
    Run without the GUI (used by the autorun entry).
#>
    [CmdletBinding()]
param(
    [switch]$Silent
)

# ---------------------------------------------------------------------------
# Self-elevate: relaunch as administrator if we are not already elevated.
# ---------------------------------------------------------------------------
$currentId = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentId)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Silent)  { $args += '-Silent' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs
    return
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
$script:ForumUrl = 'https://naifmuazzam.dev'
$script:LogFile  = Join-Path $env:TEMP 'idm-trial-reset.log'

# CLSIDs IDM uses to store trial / registration state.
$script:Clsids = @(
    '{6DDF00DB-1234-46EC-8356-27E7B2051192}',
    '{7B8E9164-324D-4A2E-A46D-0165FB2000EC}',
    '{D5B91409-A8CA-4973-9A0B-59F713D25671}',
    '{5ED60779-4DE2-4E07-B862-974CA4FF2E9C}',
    $null,                      # dynamic key (found at runtime)
    '{07999AC3-058B-40BF-984F-69EB1E554CA7}'
)

# Registry locations touched for every CLSID — HKCU only (HKLM needs TrustedInstaller).
$script:ClsidRoots = @(
    'HKCU:\Software\Classes\CLSID',
    'HKCU:\Software\Classes\Wow6432Node\CLSID'
)

# Where IDM keeps the human-readable registration values.
$script:RegKeyPaths = @(
    'HKCU:\Software\DownloadManager',
    'HKLM:\Software\Internet Download Manager',
    'HKLM:\Software\Wow6432Node\Internet Download Manager'
)

# Current user SID for HKU hive access (multi-user environments).
$script:CurrentUserSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
$script:HkuDmPath = "HKU:\$($script:CurrentUserSid)\Software\DownloadManager"

# SIDs used to (un)lock the protected keys.
$script:EveryoneSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')
$script:NobodySid   = New-Object System.Security.Principal.SecurityIdentifier('S-1-0-0')

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$stamp  $Message" | Out-File -LiteralPath $script:LogFile -Append -Encoding utf8
}

# ---------------------------------------------------------------------------
# Registry ACL helpers (native .NET - replaces SetACL.exe)
# ---------------------------------------------------------------------------
function Split-Hive {
    param([string]$Path)
    if ($Path -match '^(HKLM|HKCU|HKCR|HKU):\\(.*)$') {
        $hive = switch ($Matches[1]) {
            'HKCU' { [Microsoft.Win32.Registry]::CurrentUser }
            'HKLM' { [Microsoft.Win32.Registry]::LocalMachine }
            'HKCR' { [Microsoft.Win32.Registry]::ClassesRoot }
            'HKU'  { [Microsoft.Win32.Registry]::Users }
        }
        return @($hive, $Matches[2])
    }
    throw "Unsupported registry path: $Path"
}

function Set-RegOwner {
    param([string]$Path, [System.Security.Principal.SecurityIdentifier]$Sid)
    try {
        $hive, $sub = Split-Hive $Path
        $key = $hive.OpenSubKey($sub,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::TakeOwnership)
        if ($null -eq $key) { return $false }     # key does not exist
        $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
        $acl.SetOwner($Sid)
        $key.SetAccessControl($acl)
        $key.Close()
        return $true
    } catch {
        Write-Log "Set-RegOwner $Path -> $($Sid.Value) failed: $_"
        return $false
    }
}

function Set-RegPermission {
    param([string]$Path, [System.Security.AccessControl.RegistryRights]$Rights)
    try {
        $hive, $sub = Split-Hive $Path
        $key = $hive.OpenSubKey($sub,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        if ($null -eq $key) { return $false }     # key does not exist
        $acl = $key.GetAccessControl()
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $script:EveryoneSid,
            $Rights,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow)
        $acl.SetAccessRule($rule)
        $key.SetAccessControl($acl)
        $key.Close()
        return $true
    } catch {
        Write-Log "Set-RegPermission $Path -> $Rights failed: $_"
        return $false
    }
}

function Grant-KeyAccess {
    param([string]$Path)
    [void](Set-RegOwner -Path $Path -Sid $script:EveryoneSid)
    [void](Set-RegPermission -Path $Path -Rights ([System.Security.AccessControl.RegistryRights]::FullControl))
}

function Lock-Key {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $hive, $sub = Split-Hive $Path
        $key = $hive.OpenSubKey($sub,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::ChangePermissions -bor
            [System.Security.AccessControl.RegistryRights]::TakeOwnership)
        if ($null -eq $key) { return }
        $acl = $key.GetAccessControl()

        # Remove existing Allow rules for Everyone, then add a Deny FullControl.
        $acl.Access | Where-Object { $_.IdentityReference -eq $script:EveryoneSid } | ForEach-Object {
            $acl.RemoveAccessRule($_) | Out-Null
        }
        $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $script:EveryoneSid,
            [System.Security.AccessControl.RegistryRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Deny)
        $acl.AddAccessRule($denyRule)

        # Set owner to Nobody.
        $acl.SetOwner($script:NobodySid)
        $key.SetAccessControl($acl)
        $key.Close()
    } catch {
        Write-Log "Lock-Key $Path failed: $_"
    }
}

# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------
function Find-DynamicKey {
    # Scan HKCU CLSIDs for 'cDTvBFquXk0' value — skip HKLM (protected by TrustedInstaller).
    $root = 'HKCU:\Software\Classes\CLSID'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    try {
        Get-ChildItem -LiteralPath $root -ErrorAction Stop | ForEach-Object {
            $guid = Split-Path -Leaf $_.Name
            $psPath = Join-Path $root $guid
            if (Get-ItemProperty -LiteralPath $psPath -Name 'cDTvBFquXk0' -ErrorAction SilentlyContinue) {
                return $guid
            }
        }
    } catch {
        Write-Log "Find-DynamicKey scan of $root failed: $_"
    }
    return $null
}

function Remove-ProtectedKey {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Grant-KeyAccess -Path $Path
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Log "Deleted $Path"
    } catch {
        Write-Log "Remove-Item $Path failed: $_"
    }
}

function Remove-Value {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Remove-Value $Path\$Name failed: $_"
    }
}

function Stop-IDM {
    # IDM rewrites its licence data while running, so kill it before we touch
    # the registry. IDMan.exe = main app, IEMonitor.exe = browser integration.
    foreach ($proc in 'IDMan', 'IEMonitor', 'IDMIntegrator64', 'IDMGrHlp') {
        Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Kill(); Write-Log "Stopped process $($_.ProcessName)" } catch { Write-Log "Kill $proc failed: $_" }
        }
    }
    Start-Sleep -Milliseconds 500
}

function Reset-IDM {
    Stop-IDM
    $script:Clsids[4] = Find-DynamicKey

    foreach ($clsid in $script:Clsids) {
        if ([string]::IsNullOrWhiteSpace($clsid)) { continue }
        foreach ($root in $script:ClsidRoots) {
            Remove-ProtectedKey -Path (Join-Path $root $clsid)
        }
    }

    # Wipe licence + trial-tracking values so IDM starts a clean 30-day trial.
    $values = @(
        'FName', 'LName', 'Email', 'Serial', 'UserCode',
        'scansk', 'tvqals', 'LstCheck', 'checkdt',
        'LName1', 'FName1', 'Email1', 'Serial1',
        'tvfrdt', 'radxcnt', 'ptrk_scdt', 'LastCheckQU', 'LastCheck'
    )
    # Delete from HKCU, HKLM, and HKU hives.
    $allRegPaths = $script:RegKeyPaths + @($script:HkuDmPath)
    foreach ($rk in $allRegPaths) {
        foreach ($v in $values) {
            Remove-Value -Path $rk -Name $v
        }
    }

    # Delete entire HKLM Wow6432Node key if it exists (clean slate).
    $hklmWow = 'HKLM:\Software\Wow6432Node\Internet Download Manager'
    if (Test-Path -LiteralPath $hklmWow) {
        Remove-ProtectedKey -Path $hklmWow
    }

    Write-Log 'Reset complete.'
}

function Lock-AllKeys {
    foreach ($clsid in $script:Clsids) {
        if ([string]::IsNullOrWhiteSpace($clsid)) { continue }
        foreach ($root in $script:ClsidRoots) {
            Lock-Key -Path (Join-Path $root $clsid)
        }
    }
}

function Set-Autorun {
    param([ValidateSet('on', 'off')][string]$State)
    $dmPath = 'HKCU:\Software\DownloadManager'
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

    if ($State -eq 'off') {
        Remove-Value -Path $dmPath -Name 'auto_reset_trial'
        Remove-Value -Path $runPath -Name 'IDM trial reset'
        Write-Log 'Autorun disabled.'
        return
    }

    $resetDate = (Get-Date).AddDays(15).ToString('yyyy/MM/dd')
    if (-not (Test-Path -LiteralPath $dmPath)) { New-Item -Path $dmPath -Force | Out-Null }
    Set-ItemProperty -LiteralPath $dmPath -Name 'auto_reset_trial' -Value $resetDate

    $launcher = Join-Path $PSScriptRoot 'IDM-Trial-Reset.bat'
    $cmd = if (Test-Path -LiteralPath $launcher) { "`"$launcher`" -Silent" } else { "powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Silent" }
    Set-ItemProperty -LiteralPath $runPath -Name 'IDM trial reset' -Value $cmd
    Write-Log "Autorun enabled (reset due $resetDate)."
}

function Invoke-TrialReset {
    Reset-IDM
    Lock-AllKeys
    Write-Log 'Trial reset done — IDM will start a fresh 30-day trial.'
}





function Test-Autorun {
    try {
        $due = (Get-ItemProperty -LiteralPath 'HKCU:\Software\DownloadManager' -Name 'auto_reset_trial' -ErrorAction SilentlyContinue).auto_reset_trial
        $dt = [datetime]::MinValue
        $valid = ($null -ne $due) -and [datetime]::TryParse([string]$due, [ref]$dt)
        $cmd = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'IDM trial reset' -ErrorAction SilentlyContinue).'IDM trial reset'
        $target = $cmd -replace '"', ''
        $exists = ($target) -and (Test-Path -LiteralPath $target)
        return ($valid -and $exists)
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
Write-Log '--- idm-trial-reset starting ---'

# Kill IDM immediately so it can't rewrite registry while we work.
Stop-IDM

if ($Silent) {
    try {
        $due = (Get-ItemProperty -LiteralPath 'HKCU:\Software\DownloadManager' -Name 'auto_reset_trial' -ErrorAction SilentlyContinue).auto_reset_trial
        $dt = [datetime]::MinValue
        if (($null -ne $due) -and [datetime]::TryParse([string]$due, [ref]$dt) -and ($dt -le (Get-Date))) {
            Invoke-TrialReset
            Set-Autorun -State 'on'
        }
    } catch {
        Write-Log "Silent run failed: $_"
    }
    Write-Log '--- idm-trial-reset finished (silent) ---'
    return
}

# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Colour palette
$clrBack    = [System.Drawing.Color]::FromArgb(245, 246, 248)
$clrPrimary = [System.Drawing.Color]::FromArgb(0, 120, 215)
$clrHover   = [System.Drawing.Color]::FromArgb(16, 110, 190)
$clrText    = [System.Drawing.Color]::FromArgb(32, 32, 32)
$clrMuted   = [System.Drawing.Color]::FromArgb(110, 110, 110)
$clrOk      = [System.Drawing.Color]::FromArgb(16, 124, 16)
$clrErr     = [System.Drawing.Color]::FromArgb(196, 43, 28)
$clrInfo    = [System.Drawing.Color]::FromArgb(0, 90, 158)

function Set-Status {
    param([string]$Text, [System.Drawing.Color]$Color = $clrInfo)
    $script:statusLabel.Text = $Text
    $script:statusLabel.ForeColor = $Color
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Info {
    param([string]$Text, [string]$Title = 'IDM Trial Reset')
    [System.Windows.Forms.MessageBox]::Show($form, $Text, $Title, 'OK', 'Information') | Out-Null
}

function New-StyledButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 250, [int]$H = 44)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.SetBounds($X, $Y, $W, $H)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $clrPrimary
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_MouseEnter({ $this.BackColor = $clrHover })
    $b.Add_MouseLeave({ $this.BackColor = $clrPrimary })
    return $b
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'IDM Trial Reset'
$form.ClientSize = New-Object System.Drawing.Size(360, 210)
$form.StartPosition = 'CenterScreen'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.FormBorderStyle = 'FixedDialog'
$form.BackColor = $clrBack
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$iconPath = Join-Path $PSScriptRoot 'IDM.ico'
if (Test-Path -LiteralPath $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }

# Title bar
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'IDM Trial Reset'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $clrText
$lblTitle.SetBounds(20, 40, 320, 28)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = 'Delete all trial data so IDM starts a fresh 30-day trial.'
$lblSub.ForeColor = $clrMuted
$lblSub.SetBounds(21, 70, 320, 18)

# Buttons
$btnReset = New-StyledButton 'Reset the IDM trial now' 55 100

# Auto-reset checkbox
$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text = 'Automatically reset every 15 days'
$chkAuto.ForeColor = $clrText
$chkAuto.SetBounds(55, 155, 260, 22)
$script:suppressAutoEvent = $true
$chkAuto.Checked = Test-Autorun
$script:suppressAutoEvent = $false

# Top-right links
$lnkForum = New-Object System.Windows.Forms.LinkLabel
$lnkForum.Text = 'Discuss'
$lnkForum.SetBounds(240, 14, 60, 20)
$lnkForum.LinkColor = $clrInfo

$lnkLog = New-Object System.Windows.Forms.LinkLabel
$lnkLog.Text = 'Open log'
$lnkLog.SetBounds(300, 14, 60, 20)
$lnkLog.LinkColor = $clrInfo

# Status bar (bottom)
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.SizingGrip = $false
$statusStrip.BackColor = [System.Drawing.Color]::FromArgb(232, 233, 236)
$script:statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:statusLabel.Text = 'Ready.'
$script:statusLabel.ForeColor = $clrInfo
$statusStrip.Items.Add($script:statusLabel) | Out-Null

$form.Controls.Add($lblTitle)
$form.Controls.Add($lblSub)
$form.Controls.Add($btnReset)
$form.Controls.Add($chkAuto)
$form.Controls.Add($lnkForum)
$form.Controls.Add($lnkLog)
$form.Controls.Add($statusStrip)

# --- Events ------------------------------------------------------------------
$btnReset.Add_Click({
    $btnReset.Enabled = $false
    $btnReset.Text = 'Working...'
    Set-Status 'Resetting trial...' $clrInfo

    # Run reset on a background thread so the GUI stays responsive.
    $job = Start-Job -ScriptBlock {
        param($ScriptPath)
        # Re-invoke the script in silent mode inside the job.
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`"$ScriptPath`"" -Silent
    } -ArgumentList $PSCommandPath

    # Poll until the job finishes, pumping WinForms messages each tick.
    while ($job.State -eq 'Running') {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }

    # Capture result before removing the job.
    $failed = $job.ChildJobs[0].JobStateInfo.State -eq 'Failed'
    $errText = ''
    if ($failed) {
        $errText = ($job.ChildJobs[0].JobStateInfo.Reason.Message -join "`n")
    }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    if ($failed) {
        Write-Log "Reset failed: $errText"
        Set-Status 'Failed - see the log for details.' $clrErr
        Show-Info "Something went wrong.`nSee %TEMP%\idm-trial-reset.log" 'Error'
    } else {
        Set-Status 'Done - you have a fresh 30-day trial.' $clrOk
        Show-Info "Done! IDM will start a fresh 30-day trial.`n`nTip: tick 'Automatically reset every 15 days' below so you never run out." 'Reset IDM trial'
    }
    $btnReset.Text = 'Reset the IDM trial now'
    $btnReset.Enabled = $true
})

$chkAuto.Add_CheckedChanged({
    if ($script:suppressAutoEvent) { return }
    $chkAuto.Enabled = $false
    try {
        if ($chkAuto.Checked) {
            Set-Status 'Enabling auto-reset...' $clrInfo
            # Run reset on background thread to keep UI responsive.
            $job = Start-Job -ScriptBlock {
                param($ScriptPath)
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`"$ScriptPath`"" -Silent
            } -ArgumentList $PSCommandPath

            while ($job.State -eq 'Running') {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 50
            }

            $failed = $job.ChildJobs[0].JobStateInfo.State -eq 'Failed'
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

            if ($failed) {
                Set-Status 'Failed - see the log for details.' $clrErr
                Show-Info "Could not update auto-reset.`nSee %TEMP%\idm-trial-reset.log" 'Error'
            } else {
                Set-Autorun -State 'on'
                Set-Status 'Auto-reset enabled (every 15 days).' $clrOk
            }
        } else {
            Set-Autorun -State 'off'
            Set-Status 'Auto-reset disabled.' $clrInfo
        }
    } catch {
        Write-Log "Auto toggle failed: $_"
        Set-Status 'Failed - see the log for details.' $clrErr
        Show-Info "Could not update auto-reset.`nSee %TEMP%\idm-trial-reset.log" 'Error'
    }
    $chkAuto.Enabled = $true
})

$lnkForum.add_LinkClicked({ Start-Process $script:ForumUrl })
$lnkLog.add_LinkClicked({
    if (Test-Path -LiteralPath $script:LogFile) { Start-Process notepad.exe $script:LogFile }
    else { Show-Info 'No log yet - run a reset first.' 'Log' }
})

Write-Log '--- idm-trial-reset finished (gui) ---'
[System.Windows.Forms.Application]::Run($form)
$form.Dispose()

