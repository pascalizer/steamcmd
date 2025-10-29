<#
SteamCMD GUI installer + manager (PowerShell)
Creates a small Windows Forms GUI to:
 - download SteamCMD (steamcmd.zip)
 - extract it
 - save a small config (username, optional encrypted password, appid/steamid) to C:\Users\Administrator\steamcmd_gui_config.json
 - launch steamcmd with either anonymous login or provided credentials

NOTES / SECURITY
 - If you provide a password and check "Save credentials", the password is saved encrypted with the current Windows user DPAPI (ConvertFrom-SecureString).
   That means only the same Windows user account can decrypt it. Storing passwords on disk has risks; consider leaving credentials blank and using anonymous login.
 - Steam Guard / 2FA: interactive login may require a Steam Guard code. Automated non-interactive login might fail if Steam requests a code.
 - Run PowerShell as Administrator to write to C:\Users\Administrator.
 - To run: Unblock-File .\steamcmd_gui.ps1; Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; .\steamcmd_gui.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Config path the user requested
$ConfigPath = 'C:\Users\Administrator\steamcmd_gui_config.json'
$DefaultSteamCmdZip = "$env:TEMP\steamcmd.zip"
$DefaultInstallPath = 'C:\steamcmd'

function Load-Config {
    if (Test-Path $ConfigPath) {
        try {
            $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            return $json
        } catch {
            return $null
        }
    }
    return $null
}

function Save-Config([string]$username, [string]$encPassword, [string]$appid, [bool]$saveCreds, [string]$installPath) {
    $obj = [PSCustomObject]@{
        username = $username
        encryptedPassword = $encPassword
        appid = $appid
        saveCredentials = $saveCreds
        installPath = $installPath
        savedAt = (Get-Date).ToString('s')
    }
    $obj | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Download-SteamCMD([string]$outPath) {
    $url = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
    try {
        # Use Invoke-WebRequest rather than wget alias to be explicit
        Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Download failed: $($_.Exception.Message)", "Error", 'OK', 'Error') | Out-Null
        return $false
    }
}

function Extract-ZipTo([string]$zipPath, [string]$dest) {
    try {
        if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
        Expand-Archive -Path $zipPath -DestinationPath $dest -Force
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Extraction failed: $($_.Exception.Message)", "Error", 'OK', 'Error') | Out-Null
        return $false
    }
}

function Launch-SteamCMD([string]$steamCmdPath, [string]$username, [System.Security.SecureString]$securePassword, [bool]$anonymous, [string]$appid, [string]$installPath) {
    $exe = Join-Path $steamCmdPath 'steamcmd.exe'
    if (-not (Test-Path $exe)) {
        [System.Windows.Forms.MessageBox]::Show("steamcmd.exe not found in $steamCmdPath", "Error", 'OK', 'Error') | Out-Null
        return
    }

    # Build argument list
    if ($anonymous) {
        $loginArg = '+login anonymous'
    } else {
        # Convert secure password to plain for command arg (will be visible to system processes). We only do this at runtime.
        $plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
        $loginArg = "+login $username $plainPwd"
    }

    $cmds = @($loginArg)
    if ($appid -and $appid -ne '') {
        if (-not (Test-Path $installPath)) { New-Item -ItemType Directory -Path $installPath -Force | Out-Null }
        $cmds += "+force_install_dir $installPath"
        $cmds += "+app_update $appid validate"
    }
    $cmds += '+quit'

    $args = $cmds -join ' '

    # Start steamcmd in a new window so the user can interact (for Steam Guard / 2FA)
    Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $steamCmdPath -NoNewWindow -Wait
}

# Build GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SteamCMD GUI — Download & Manage'
$form.Size = New-Object System.Drawing.Size(560,380)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# Controls
$lblInstall = New-Object System.Windows.Forms.Label
$lblInstall.Location = New-Object System.Drawing.Point(10,12)
$lblInstall.Size = New-Object System.Drawing.Size(120,20)
$lblInstall.Text = 'Install path:'
$form.Controls.Add($lblInstall)

$txtInstall = New-Object System.Windows.Forms.TextBox
$txtInstall.Location = New-Object System.Drawing.Point(130,10)
$txtInstall.Size = New-Object System.Drawing.Size(320,20)
$txtInstall.Text = $DefaultInstallPath
$form.Controls.Add($txtInstall)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(460,8)
$btnBrowse.Size = New-Object System.Drawing.Size(75,24)
$btnBrowse.Text = 'Browse'
$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.SelectedPath = $txtInstall.Text
    if ($fbd.ShowDialog() -eq 'OK') { $txtInstall.Text = $fbd.SelectedPath }
})
$form.Controls.Add($btnBrowse)

$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Location = New-Object System.Drawing.Point(10,50)
$lblUser.Size = New-Object System.Drawing.Size(120,20)
$lblUser.Text = 'Steam username:'
$form.Controls.Add($lblUser)

$txtUser = New-Object System.Windows.Forms.TextBox
$txtUser.Location = New-Object System.Drawing.Point(130,48)
$txtUser.Size = New-Object System.Drawing.Size(320,20)
$form.Controls.Add($txtUser)

$lblPass = New-Object System.Windows.Forms.Label
$lblPass.Location = New-Object System.Drawing.Point(10,86)
$lblPass.Size = New-Object System.Drawing.Size(120,20)
$lblPass.Text = 'Password (optional):'
$form.Controls.Add($lblPass)

$txtPass = New-Object System.Windows.Forms.MaskedTextBox
$txtPass.Location = New-Object System.Drawing.Point(130,84)
$txtPass.Size = New-Object System.Drawing.Size(320,20)
$txtPass.UseSystemPasswordChar = $true
$form.Controls.Add($txtPass)

$chkAnon = New-Object System.Windows.Forms.CheckBox
$chkAnon.Location = New-Object System.Drawing.Point(130,114)
$chkAnon.Size = New-Object System.Drawing.Size(240,20)
$chkAnon.Text = 'Login anonymously (recommended)'
$chkAnon.Checked = $true
$form.Controls.Add($chkAnon)

$chkSaveCreds = New-Object System.Windows.Forms.CheckBox
$chkSaveCreds.Location = New-Object System.Drawing.Point(130,138)
$chkSaveCreds.Size = New-Object System.Drawing.Size(320,20)
$chkSaveCreds.Text = 'Save credentials (encrypted with current Windows user)'
$chkSaveCreds.Checked = $false
$form.Controls.Add($chkSaveCreds)

$lblApp = New-Object System.Windows.Forms.Label
$lblApp.Location = New-Object System.Drawing.Point(10,172)
$lblApp.Size = New-Object System.Drawing.Size(120,20)
$lblApp.Text = 'AppID / Server ID:'
$form.Controls.Add($lblApp)

$txtApp = New-Object System.Windows.Forms.TextBox
$txtApp.Location = New-Object System.Drawing.Point(130,170)
$txtApp.Size = New-Object System.Drawing.Size(120,20)
$form.Controls.Add($txtApp)

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Location = New-Object System.Drawing.Point(10,200)
$lblInfo.Size = New-Object System.Drawing.Size(520,60)
$lblInfo.Text = "Notes: Automated login may trigger Steam Guard / 2FA. If you see a prompt in the SteamCMD window asking for a code, provide it there.\nSaved passwords are encrypted per Windows user account."
$form.Controls.Add($lblInfo)

# Buttons
$btnDownload = New-Object System.Windows.Forms.Button
$btnDownload.Location = New-Object System.Drawing.Point(10,270)
$btnDownload.Size = New-Object System.Drawing.Size(120,30)
$btnDownload.Text = 'Download SteamCMD'
$btnDownload.Add_Click({
    $out = $DefaultSteamCmdZip
    $ok = Download-SteamCMD -outPath $out
    if ($ok) { [System.Windows.Forms.MessageBox]::Show("Downloaded to $out", "OK", 'OK', 'Information') | Out-Null }
})
$form.Controls.Add($btnDownload)

$btnExtract = New-Object System.Windows.Forms.Button
$btnExtract.Location = New-Object System.Drawing.Point(140,270)
$btnExtract.Size = New-Object System.Drawing.Size(120,30)
$btnExtract.Text = 'Extract / Install'
$btnExtract.Add_Click({
    $out = $DefaultSteamCmdZip
    if (-not (Test-Path $out)) {
        $r = [System.Windows.Forms.MessageBox]::Show("steamcmd.zip not found in $out. Download first?", "Missing", 'YesNo', 'Question')
        if ($r -eq 'Yes') { if (-not (Download-SteamCMD -outPath $out)) { return } }
        else { return }
    }
    $dest = $txtInstall.Text
    if (Extract-ZipTo -zipPath $out -dest $dest) { [System.Windows.Forms.MessageBox]::Show("Extracted to $dest", "OK", 'OK', 'Information') | Out-Null }
})
$form.Controls.Add($btnExtract)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Location = New-Object System.Drawing.Point(270,270)
$btnSave.Size = New-Object System.Drawing.Size(120,30)
$btnSave.Text = 'Save config'
$btnSave.Add_Click({
    $user = $txtUser.Text
    $pwdPlain = $txtPass.Text
    $appid = $txtApp.Text
    $installPath = $txtInstall.Text
    $saveCreds = $chkSaveCreds.Checked

    $enc = $null
    if ($pwdPlain -and $pwdPlain -ne '') {
        $secure = ConvertTo-SecureString $pwdPlain -AsPlainText -Force
        $enc = $secure | ConvertFrom-SecureString
    }

    Save-Config -username $user -encPassword $enc -appid $appid -saveCreds $saveCreds -installPath $installPath
    [System.Windows.Forms.MessageBox]::Show("Config saved to $ConfigPath", "OK", 'OK', 'Information') | Out-Null
})
$form.Controls.Add($btnSave)

$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Location = New-Object System.Drawing.Point(400,270)
$btnLoad.Size = New-Object System.Drawing.Size(120,30)
$btnLoad.Text = 'Load config'
$btnLoad.Add_Click({
    $cfg = Load-Config
    if (-not $cfg) { [System.Windows.Forms.MessageBox]::Show("No config found at $ConfigPath", "Info", 'OK', 'Information') | Out-Null; return }
    if ($cfg.username) { $txtUser.Text = $cfg.username }
    if ($cfg.appid) { $txtApp.Text = $cfg.appid }
    if ($cfg.installPath) { $txtInstall.Text = $cfg.installPath }
    if ($cfg.encryptedPassword) {
        try {
            $sec = $cfg.encryptedPassword | ConvertTo-SecureString
            # We don't display password in UI; indicate saved creds
            $txtPass.Text = ''
            $chkSaveCreds.Checked = $true
            [System.Windows.Forms.MessageBox]::Show("Encrypted credentials loaded (password will be used when launching).", "Info", 'OK', 'Information') | Out-Null
            # Keep encrypted password in tag for retrieval at launch
            $form.Tag = @{ encryptedPassword = $cfg.encryptedPassword }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to decrypt saved password. It may belong to a different Windows user.", "Warning", 'OK', 'Warning') | Out-Null
        }
    }
})
$form.Controls.Add($btnLoad)

$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Location = New-Object System.Drawing.Point(10,312)
$btnLaunch.Size = New-Object System.Drawing.Size(510,32)
$btnLaunch.Text = 'Launch SteamCMD (this will open SteamCMD console)'
$btnLaunch.Font = New-Object System.Drawing.Font($btnLaunch.Font.FontFamily,10)
$btnLaunch.Add_Click({
    $installPath = $txtInstall.Text
    $steamCmdPath = $installPath

    if (-not (Test-Path (Join-Path $steamCmdPath 'steamcmd.exe'))) {
        $r = [System.Windows.Forms.MessageBox]::Show("steamcmd.exe not found in $steamCmdPath. Extract/install now?", "Missing", 'YesNo', 'Question')
        if ($r -eq 'Yes') {
            $out = $DefaultSteamCmdZip
            if (-not (Test-Path $out)) { if (-not (Download-SteamCMD -outPath $out)) { return } }
            if (-not (Extract-ZipTo -zipPath $out -dest $steamCmdPath)) { return }
        } else { return }
    }

    $anonymous = $chkAnon.Checked
    $username = $txtUser.Text
    $appid = $txtApp.Text

    # Determine secure password: priority - UI typed -> config encrypted -> null
    $securePwd = $null
    if (-not $anonymous) {
        if ($txtPass.Text -and $txtPass.Text -ne '') {
            $securePwd = ConvertTo-SecureString $txtPass.Text -AsPlainText -Force
        } elseif ($form.Tag -and $form.Tag.encryptedPassword) {
            try {
                $securePwd = $form.Tag.encryptedPassword | ConvertTo-SecureString
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Cannot decrypt saved password. Please type your password into the form.", "Error", 'OK', 'Error') | Out-Null
                return
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Password not provided. Either type it or enable anonymous login.", "Error", 'OK', 'Error') | Out-Null
            return
        }
    }

    Launch-SteamCMD -steamCmdPath $steamCmdPath -username $username -securePassword $securePwd -anonymous $anonymous -appid $appid -installPath $installPath
})
$form.Controls.Add($btnLaunch)

# Try to pre-load config
$cfg = Load-Config
if ($cfg) {
    if ($cfg.username) { $txtUser.Text = $cfg.username }
    if ($cfg.appid) { $txtApp.Text = $cfg.appid }
    if ($cfg.installPath) { $txtInstall.Text = $cfg.installPath }
    if ($cfg.encryptedPassword) { $form.Tag = @{ encryptedPassword = $cfg.encryptedPassword }; $chkSaveCreds.Checked = $cfg.saveCredentials }
}

[void] $form.ShowDialog()
