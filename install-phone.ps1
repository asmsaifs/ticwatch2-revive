# ticwatch2-revive - install / update the phone-side app(s) on an Android phone.
# Windows: double-click install-phone.bat, or run in PowerShell:  .\install-phone.ps1 [options]
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'lib\common.ps1')

function Usage {
@'
Usage: install-phone.ps1 [options]

Installs or updates the phone apps listed in manifest.tsv (target "phone") on an Android
phone connected with USB debugging or Wireless debugging. Safe to re-run: apps that are
already current are left alone.

  --serial ID            use this adb device (see: adb devices) when several are attached
  --pair HOST:PORT CODE  pair with a phone over Wireless debugging first (Android 11+),
                         using the pairing address and 6-digit code shown on the phone
  --connect HOST:PORT    connect to a phone over Wireless debugging (the main address, not the pairing one)
  --force                if an app is installed with a different signing key, uninstall it first
  --offline              do not look for newer files online (no git pull / download)
  --yes                  answer "yes" to prompts
  --dry-run              show what would be done, change nothing
  -h, --help             this text
'@ | Write-Host
}

$serial = ''; $pairAddr = ''; $pairCode = ''; $connect = ''
$script:Force = $false; $script:Offline = $false; $script:AssumeYes = $false; $script:DryRun = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ($args[$i]) {
        '^-{1,2}serial$'  { $i++; $serial = [string]$args[$i]; if (-not $serial) { Die '--serial needs a device id' } }
        '^-{1,2}pair$'    { $pairAddr = [string]$args[$i + 1]; $pairCode = [string]$args[$i + 2]; $i += 2
                            if (-not $pairAddr -or -not $pairCode) { Die '--pair needs HOST:PORT and the 6-digit CODE' } }
        '^-{1,2}connect$' { $i++; $connect = [string]$args[$i]; if (-not $connect) { Die '--connect needs HOST:PORT' } }
        '^-{1,2}force$'   { $script:Force = $true }
        '^-{1,2}offline$' { $script:Offline = $true }
        '^-{1,2}(yes|y)$' { $script:AssumeYes = $true }
        '^-{1,2}dry-?run$' { $script:DryRun = $true }
        '^(-h|--help|-help|/\?)$' { Usage; exit 0 }
        default { Usage; Die "unknown option: $($args[$i])" }
    }
}

Init-Paths $here
Say 'ticwatch2-revive - phone installer'

Step 'Looking for newer app versions'
Sync-Repo

Step 'Android Debug Bridge'
Find-Adb; Ok "adb: $($script:AdbExe)"
Adb @('start-server') | Out-Null

if ($pairAddr) { Step 'Pairing'; (Adb @('pair', $pairAddr, $pairCode)).Out.Trim() | ForEach-Object { Say "    $_" } }
if ($connect) { (Adb @('connect', $connect)).Out.Trim() | ForEach-Object { Say "    $_" }; Start-Sleep 1 }

Step 'Finding the phone'
$phone = $null
if ($serial) { $phone = $serial }
else {
    $cands = @()
    foreach ($s in (Online-Serials)) { if (-not (Is-Watch $s)) { $cands += $s } }
    if ($cands.Count -eq 1) { $phone = $cands[0] }
    elseif ($cands.Count -gt 1) {
        Say '  several phones attached:'
        for ($k = 0; $k -lt $cands.Count; $k++) { Say ("    {0}) {1}  ({2})" -f ($k + 1), $cands[$k], (DevSh $cands[$k] 'getprop ro.product.model').Trim()) }
        $n = Read-Host "  Which one? [1-$($cands.Count)]"
        if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $cands.Count) { $phone = $cands[[int]$n - 1] } else { Die 'invalid choice' }
    }
}
if (-not $phone) { Die 'no phone found. Enable Developer options > USB debugging (or Wireless debugging and use --pair / --connect), then re-run.' }
Ok ("phone: {0} ({1}, Android {2})" -f $phone, (DevSh $phone 'getprop ro.product.model').Trim(), (DevSh $phone 'getprop ro.build.version.release').Trim())

Step 'Installing apps'
$okAll = Install-Target $phone 'phone'

if ($okAll -and -not $script:DryRun) {
    $pkg = 'org.xzwatch.bridge.phone'
    if (Installed-Path $phone $pkg) {
        Step 'Granting permissions to Install on Watch'
        foreach ($perm in @('android.permission.POST_NOTIFICATIONS', 'android.permission.BLUETOOTH_CONNECT')) {
            $o = DevSh $phone "pm grant $pkg $perm"
            $short = $perm.Split('.')[-1]
            if ($o.Trim()) { Say "  (could not grant $short - it will ask on first use)" } else { Ok $short }
        }
        $o = DevSh $phone "appops set $pkg MANAGE_EXTERNAL_STORAGE allow"
        if ($o.Trim()) { Say '  (could not grant All-files access - allow it in Settings > Apps > Special access)' } else { Ok 'All-files access' }
    }
}

Step 'Finished'
if ($okAll) { Ok 'all done' } else { Warn 'finished with errors - see messages above' }
@'

  "Install on Watch" now appears when you open an .apk file (Open with...).
  Re-run this script any time to pick up new versions.
'@ | Write-Host
if (-not $okAll) { exit 1 }
