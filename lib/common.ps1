# Shared helpers for install-watch.ps1 / install-phone.ps1 (Windows PowerShell 5.1+ and PowerShell 7).
# Dot-sourced, never executed directly. Mirrors lib/common.sh.

# ----------------------------------------------------------------- config
# Used only when the folder is not a git clone with an "origin" remote.
# Change it if you fork the repository, or set $env:TICWATCH2_REVIVE_RAW to override.
$script:DefaultRaw = 'https://raw.githubusercontent.com/asmsaifs/ticwatch2-revive/main'
$script:PlatformToolsUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------- output
function Say([string]$m)  { Write-Host $m }
function Step([string]$m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Ok([string]$m)   { Write-Host '  OK ' -ForegroundColor Green -NoNewline; Write-Host $m }
function Warn([string]$m) { Write-Host '  !  ' -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Err([string]$m)  { Write-Host '  X  ' -ForegroundColor Red -NoNewline; Write-Host $m }
function Die([string]$m)  { Err $m; exit 1 }
function Confirm-Yes([string]$q) {
    if ($script:AssumeYes) { return $true }
    $a = Read-Host "  $q [y/N]"
    return ($a -match '^(y|yes)$')
}

# ----------------------------------------------------------------- native process helper (no stderr-as-error surprises, stdin closed)
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $quoted = @()
    foreach ($a in $Arguments) {
        if ($a -match '[\s"]' -or $a -eq '') { $quoted += ('"' + ($a -replace '"', '\"') + '"') } else { $quoted += $a }
    }
    $psi.Arguments = ($quoted -join ' ')
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $text = ($out + $errTask.Result).Replace("`r", '')
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $text }
}
function Adb([string[]]$a) { return (Invoke-Native $script:AdbExe $a) }
function AdbS([string]$serial, [string[]]$a) { return (Invoke-Native $script:AdbExe (@('-s', $serial) + $a)) }
function DevSh([string]$serial, [string]$cmd) { return ((AdbS $serial @('shell', $cmd)).Out) }

# ----------------------------------------------------------------- files
function Md5Of([string]$path) { return (Get-FileHash -Algorithm MD5 -LiteralPath $path).Hash.ToLower() }
function HttpGet([string]$url, [string]$out) {
    try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out -TimeoutSec 120 | Out-Null; return $true } catch { return $false }
}
function Read-Tsv([string]$path) {
    $rows = @()
    foreach ($line in (Get-Content -LiteralPath $path)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        $rows += , ($line -split "`t")
    }
    return , $rows
}

function Init-Paths([string]$here) {
    $script:Root = $here
    $script:Cache = Join-Path $here '.cache'
    $script:Manifest = Join-Path $here 'manifest.tsv'
    $script:SysApps = Join-Path $here 'system-apps.tsv'
    if (-not (Test-Path $script:Manifest)) { Die 'manifest.tsv not found next to the script - run it from the repository folder' }
}

function Get-RawBase {
    if ($env:TICWATCH2_REVIVE_RAW) { return $env:TICWATCH2_REVIVE_RAW }
    if ((Test-Path (Join-Path $script:Root '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $url = (Invoke-Native 'git' @('-C', $script:Root, 'remote', 'get-url', 'origin')).Out.Trim()
        $br = (Invoke-Native 'git' @('-C', $script:Root, 'rev-parse', '--abbrev-ref', 'HEAD')).Out.Trim()
        if (-not $br) { $br = 'main' }
        $path = $null
        if ($url -match '^https://github\.com/(.+?)(\.git)?$') { $path = $Matches[1] }
        elseif ($url -match '^git@github\.com:(.+?)(\.git)?$') { $path = $Matches[1] }
        if ($path) { return "https://raw.githubusercontent.com/$path/$br" }
    }
    return $script:DefaultRaw
}

function Sync-Repo {
    if ($script:Offline) { Say '  offline mode: using the files in this folder'; return }
    if ((Test-Path (Join-Path $script:Root '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $before = (Invoke-Native 'git' @('-C', $script:Root, 'rev-parse', 'HEAD')).Out.Trim()
        $r = Invoke-Native 'git' @('-C', $script:Root, 'pull', '--ff-only', '-q')
        if ($r.Code -eq 0) {
            Ok 'repository updated (git pull)'
            # The installer scripts themselves changed: the caller restarts so the new code runs now.
            if ($before) {
                $d = Invoke-Native 'git' @('-C', $script:Root, 'diff', '--quiet', $before, 'HEAD', '--', '*.ps1', '*.bat', 'lib')
                if ($d.Code -eq 1) { $script:ScriptsUpdated = $true }
            }
            return
        }
        Warn 'git pull did not work (local changes?) - trying a plain download instead'
    }
    $raw = Get-RawBase
    if (-not $raw) { Warn 'no repository URL known (edit $DefaultRaw in lib/common.ps1) - using local files'; return }
    New-Item -ItemType Directory -Force -Path $script:Cache | Out-Null
    $cm = Join-Path $script:Cache 'manifest.tsv'
    if (-not (HttpGet "$raw/manifest.tsv" $cm)) { Warn "cannot reach $raw - using the files in this folder"; return }
    $cs = Join-Path $script:Cache 'system-apps.tsv'
    if (HttpGet "$raw/system-apps.tsv" $cs) { $script:SysApps = $cs }
    $script:Manifest = $cm
    $n = 0
    foreach ($r in (Read-Tsv $script:Manifest)) {
        $file = $r[2]; $md5 = $r[3]; $name = $r[4]
        $local = Join-Path $script:Root $file; $cached = Join-Path $script:Cache $file
        if ((Test-Path $local) -and ((Md5Of $local) -eq $md5)) { continue }
        if ((Test-Path $cached) -and ((Md5Of $cached) -eq $md5)) { continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $cached) | Out-Null
        Say "  downloading newer $name ($file)"
        if ((HttpGet "$raw/$file" $cached) -and ((Md5Of $cached) -eq $md5)) { $n++ }
        else { Remove-Item -Force -ErrorAction SilentlyContinue $cached; Warn "download of $file failed or does not match the manifest - keeping the local copy" }
    }
    Ok "online sync done ($n file(s) downloaded)"
}

function Apk-For([string]$file, [string]$md5) {
    $cached = Join-Path $script:Cache $file
    if ((Test-Path $cached) -and ((Md5Of $cached) -eq $md5)) { return $cached }
    return (Join-Path $script:Root $file)
}

# ----------------------------------------------------------------- adb
function Find-Adb {
    $script:AdbExe = $null
    if ($env:ADB_BIN -and (Test-Path $env:ADB_BIN)) { $script:AdbExe = $env:ADB_BIN }
    if (-not $script:AdbExe) {
        $c = Get-Command adb -ErrorAction SilentlyContinue
        if ($c) { $script:AdbExe = $c.Source }
    }
    if (-not $script:AdbExe) {
        $cands = @((Join-Path $script:Root '.platform-tools\platform-tools\adb.exe'))
        if ($env:LOCALAPPDATA) { $cands += (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe') }
        if ($env:ANDROID_HOME) { $cands += (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe') }
        foreach ($p in $cands) { if (Test-Path $p) { $script:AdbExe = $p; break } }
    }
    if ($script:AdbExe) { return }
    Warn 'adb (Android platform-tools) not found'
    if (Confirm-Yes "Download Google's official platform-tools (about 15 MB) into $($script:Root)\.platform-tools ?") {
        $dir = Join-Path $script:Root '.platform-tools'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $zip = Join-Path $dir 'pt.zip'
        if (-not (HttpGet $script:PlatformToolsUrl $zip)) { Die 'download failed' }
        Expand-Archive -Force -LiteralPath $zip -DestinationPath $dir
        Remove-Item -Force $zip
        $script:AdbExe = Join-Path $dir 'platform-tools\adb.exe'
        if (-not (Test-Path $script:AdbExe)) { Die 'platform-tools unpacked but adb.exe not found' }
    } else {
        Die 'adb is required. Install platform-tools (https://developer.android.com/tools/releases/platform-tools) and re-run.'
    }
}

function Online-Serials {
    $r = Adb @('devices')
    $list = @()
    foreach ($line in ($r.Out -split "`n" | Select-Object -Skip 1)) {
        $f = $line.Trim() -split '\s+'
        if ($f.Count -ge 2 -and $f[1] -eq 'device') { $list += $f[0] }
    }
    return , $list
}
function Product-Of([string]$s) { return (DevSh $s 'getprop ro.product.device').Trim() }
function Is-Watch([string]$s) { return ((Product-Of $s) -eq 'mercury') }

# ----------------------------------------------------------------- apps
function Installed-Path([string]$s, [string]$pkg) {
    foreach ($l in ((DevSh $s "pm path $pkg") -split "`n")) { if ($l.StartsWith('package:')) { return $l.Substring(8).Trim() } }
    return ''
}
function Installed-Md5([string]$s, [string]$pkg) {
    $p = Installed-Path $s $pkg
    if (-not $p) { return '' }
    $o = DevSh $s "md5sum $p 2>/dev/null || md5 $p"
    foreach ($l in ($o -split "`n")) { $t = $l.Trim(); if ($t) { return ($t -split '\s+')[0] } }
    return ''
}

function Install-App([string]$s, [string]$apk, [string]$pkg, [string]$name) {
    $want = Md5Of $apk; $have = Installed-Md5 $s $pkg
    if ($have -and ($have -eq $want)) { Ok "$name is up to date"; return $true }
    if ($have) { Say "  updating $name ..." } else { Say "  installing $name ..." }
    if ($script:DryRun) { Say "  (dry run) adb install -r $apk"; return $true }
    $out = (AdbS $s @('install', '-r', $apk)).Out
    if ($out -match 'Success') { Ok "$name installed"; return $true }
    if ($out -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|INSTALL_FAILED_SIGNATURE') {
        if ($script:Force) {
            Warn "$name was signed with a different key - uninstalling it first (its data is erased)"
            AdbS $s @('uninstall', $pkg) | Out-Null
            $out = (AdbS $s @('install', $apk)).Out
            if ($out -match 'Success') { Ok "$name installed"; return $true }
            Err "${name}: $($out.Trim())"; return $false
        }
        Err "$name is installed with a different signing key. Re-run with --force to replace it (this erases the app's data)."; return $false
    }
    if ($out -match 'INSTALL_FAILED_DEPRECATED_SDK_VERSION') {
        $out = (AdbS $s @('install', '-r', '--bypass-low-target-sdk-block', $apk)).Out
        if ($out -match 'Success') { Ok "$name installed (low-target-SDK block bypassed)"; return $true }
    }
    $last = ($out.Trim() -split "`n")[-1]
    Err "${name}: $last"; return $false
}

# '32' if the device can run 32-bit ARM code (armeabi-v7a), '64' if it is a 64-bit-only phone
# (newer Snapdragon / Tensor / Dimensity chips). The Mobvoi apps only carry 32-bit native libraries,
# so 64-bit-only phones get the '-arm64' builds with those libraries stripped out.
function Abi-Class([string]$s) {
    $l32 = (DevSh $s 'getprop ro.product.cpu.abilist32').Trim()
    $l = (DevSh $s 'getprop ro.product.cpu.abilist').Trim()
    if ((",$l32,$l," -match ',armeabi-v7a,') -or (",$l32,$l," -match ',armeabi,')) { return '32' }
    if ($l) { return '64' } else { return '32' }
}

# Rows with target '<target>32' / '<target>64' are only used on devices of that ABI class.
function Install-Target([string]$s, [string]$want) {
    $rc = $true; $n = 0
    $cls = Abi-Class $s
    foreach ($r in (Read-Tsv $script:Manifest)) {
        if ($r[0] -ne $want -and $r[0] -ne "$want$cls") { continue }
        $pkg = $r[1]; $file = $r[2]; $md5 = $r[3]; $name = $r[4]
        $apk = Apk-For $file $md5
        if (-not (Test-Path $apk)) { Err "$file is listed in the manifest but missing"; $rc = $false; continue }
        if (-not (Install-App $s $apk $pkg $name)) { $rc = $false }
        $n++
    }
    if ($n -eq 0) { Warn "the manifest lists no $want apps" }
    return $rc
}

function StayAwake([string]$s, [bool]$on) { try { DevSh $s ("svc power stayon " + $(if ($on) { 'true' } else { 'false' })) | Out-Null } catch { } }

function Apply-SysApps([string]$s, [string]$mode) {
    if (-not (Test-Path $script:SysApps)) { Warn 'no system-apps.tsv'; return }
    $present = (DevSh $s 'pm list packages') -split "`n" | ForEach-Object { $_.Trim() }
    $state = (DevSh $s 'pm list packages -d') -split "`n" | ForEach-Object { $_.Trim() }
    $triedRoot = $false
    foreach ($r in (Read-Tsv $script:SysApps)) {
        $pkg = $r[0]; $on = $r[1]; $why = if ($r.Count -gt 2) { $r[2] } else { '' }
        if ($on -ne 'yes') { continue }
        if ($present -notcontains "package:$pkg") { Say "  ${pkg}: not on this watch, skipped"; continue }
        $isDisabled = $state -contains "package:$pkg"
        if ($mode -eq 'disable' -and $isDisabled) { Ok "$pkg already disabled"; continue }
        if ($mode -eq 'enable' -and -not $isDisabled) { Ok "$pkg already enabled"; continue }
        if ($script:DryRun) { Say "  (dry run) pm $mode $pkg"; continue }
        $out = DevSh $s "pm $mode $pkg"
        if ($out -match 'new state') {
            if ($mode -eq 'disable') { Ok "$pkg disabled - $why" } else { Ok "$pkg enabled" }
        } else {
            if (-not $triedRoot) {
                $triedRoot = $true
                AdbS $s @('root') | Out-Null; Start-Sleep 3; Adb @('connect', $s) | Out-Null; Start-Sleep 1
                $out = DevSh $s "pm $mode $pkg"
                if ($out -match 'new state') { Ok "$pkg ${mode}d (needed adb root)"; continue }
            }
            Err "${pkg}: $(($out.Trim() -split "`n")[0])"
        }
    }
}

function Pick-Watch {
    $script:Watch = $null
    if ($script:Addr) { Adb @('connect', $script:Addr) | Out-Null; Start-Sleep 1 }
    for ($tries = 1; $tries -le 3; $tries++) {
        foreach ($s in (Online-Serials)) { if (Is-Watch $s) { $script:Watch = $s; break } }
        if ($script:Watch) { break }
        Say '  No Ticwatch 2 found yet.'
        Say '  On the watch: Settings > About > tap Build number 7 times > Developer options > ADB debugging + Debug over Wi-Fi.'
        if ($tries -ge 3) { Die 'no Ticwatch 2 found. Enable ADB debugging on the watch and connect it (see README, Connect the watch).' }
        $a = Read-Host '  Watch address as IP:PORT (shown in Developer options; empty = retry)'
        if ($a) { (Adb @('connect', $a)).Out.Trim() | ForEach-Object { Say "    $_" }; Start-Sleep 1 }
    }
    Ok "watch found: $($script:Watch)"
}

# ----------------------------------------------------------------- Ticwear home patch
# Makes every voice launch of the watch (swipe right on the watch face, "OK Tico", the wrist gesture)
# open Sonora instead of Tico; if Sonora is missing, Tico still opens. Ticwear home is a platform-signed
# system app, so its APK cannot be re-signed: only its compiled code (the .odex) is replaced. The
# patched classes.dex is compiled ON the watch by the watch's own dex2oat against its own boot image.
# Needs adb root (the userdebug ROM from the README has it). Built for Tic_4.13.0_intl_a1 only: on any
# other Ticwear home the step is skipped. The original odex is kept in /system/xzpatch (survives a
# factory reset); --restore puts it back.
$script:HomePkg = 'com.mobvoi.ticwear.home'
$script:HomeOdex = '/system/priv-app/MobvoiWearHome/arm/MobvoiWearHome.odex'
$script:HomeApk = '/system/priv-app/MobvoiWearHome/MobvoiWearHome.apk'
$script:HomeOrigMd5 = '1fd6479ec9b71dc3108e2b594302cc2a'   # stock odex of Tic_4.13.0_intl_a1
$script:HomeBak = '/system/xzpatch'
$script:HomeTmp = '/data/local/tmp/xzpatch'

function Dev-Root([string]$s) {
    if ((DevSh $s 'id') -match 'uid=0') { return $true }
    AdbS $s @('root') | Out-Null
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep 2
        if ($s -match ':') { Adb @('connect', $s) | Out-Null }
        if ((DevSh $s 'id') -match 'uid=0') { return $true }
    }
    return $false
}

function Dev-Md5([string]$s, [string]$path) {
    foreach ($line in ((DevSh $s "md5 $path 2>/dev/null || md5sum $path 2>/dev/null") -split "`n")) {
        $f = $line.Trim() -split '\s+'
        if ($f[0] -match '^[0-9a-f]{32}$') { return $f[0] }
    }
    return ''
}

function Restart-Home([string]$s) {
    try { DevSh $s "am force-stop $($script:HomePkg); sleep 2; am start -a android.intent.action.MAIN -c android.intent.category.HOME" | Out-Null } catch { }
}

# Swap an odex already on the watch into place, atomically (same file system rename).
function Swap-HomeOdex([string]$s, [string]$src) {
    $o = $script:HomeOdex
    return ((DevSh $s "cp $src $o.new && chmod 644 $o.new && chown root:root $o.new && chcon u:object_r:system_file:s0 $o.new && mv $o.new $o && sync && echo SWAP_OK") -match 'SWAP_OK')
}

function Home-Patch([string]$s, [string]$mode) {
    $bakFile = "$($script:HomeBak)/MobvoiWearHome.odex.orig"; $tmp = $script:HomeTmp
    if (-not (Dev-Root $s)) { Warn 'skipped: needs adb root (the userdebug ROM in README > Flash the old ROM has it)'; return $true }
    $cur = Dev-Md5 $s $script:HomeOdex
    if (-not $cur) { Warn 'skipped: Ticwear home not found on this watch'; return $true }
    $mark = ((DevSh $s "cat $($script:HomeBak)/applied 2>/dev/null").Trim() -split '\s+')
    $mdex = if ($mark.Count -ge 1 -and $mark[0] -match '^[0-9a-f]{32}$') { $mark[0] } else { '' }
    $modex = if ($mark.Count -ge 2) { $mark[1] } else { '' }
    $bak = Dev-Md5 $s $bakFile

    if ($mode -eq 'restore') {
        if ($cur -eq $script:HomeOrigMd5) { Ok 'Ticwear home is the original'; return $true }
        if ($bak -ne $script:HomeOrigMd5) { Err 'no backup of the original Ticwear home on the watch - reflash the ROM to undo'; return $false }
        if ($script:DryRun) { Say "  (dry run) restore $($script:HomeOdex) from $($script:HomeBak)"; return $true }
        AdbS $s @('remount') | Out-Null
        if (-not (Swap-HomeOdex $s $bakFile)) { Err 'could not restore the original Ticwear home'; return $false }
        DevSh $s "rm -f $($script:HomeBak)/applied" | Out-Null
        Restart-Home $s; Ok 'original Ticwear home restored (voice opens Tico again)'; return $true
    }

    $row = $null
    foreach ($r in (Read-Tsv $script:Manifest)) { if ($r[0] -eq 'watch-home') { $row = $r; break } }
    if (-not $row) { Warn 'the manifest lists no home patch'; return $true }
    $file = $row[2]; $want = $row[3]
    $dex = Apk-For $file $want
    if (-not (Test-Path $dex)) { Err "$file is listed in the manifest but missing"; return $false }

    if ($cur -eq $script:HomeOrigMd5) { Say '  patching Ticwear home ...' }
    elseif ($mdex -and $modex -eq $cur) {
        if ($mdex -eq $want) { Ok 'Ticwear home patch is up to date'; return $true }
        if ($bak -ne $script:HomeOrigMd5) { Err 'patched Ticwear home without a backup of the original - skipped'; return $false }
        Say '  updating the Ticwear home patch ...'
    } else {
        Warn "skipped: this watch's Ticwear home is not the Tic_4.13.0_intl_a1 one the patch was made for"; return $true
    }
    if ($script:DryRun) { Say "  (dry run) compile $file on the watch and replace $($script:HomeOdex)"; return $true }

    $out = (AdbS $s @('remount')).Out
    if ($out -notmatch 'succeeded') { Err "cannot make /system writable: $($out.Trim())"; return $false }
    if ($bak -ne $script:HomeOrigMd5) {
        if ((DevSh $s "mkdir -p $($script:HomeBak) && cp $($script:HomeOdex) $bakFile && sync && echo BAK_OK") -notmatch 'BAK_OK') { Err 'could not back up the original Ticwear home - nothing changed'; return $false }
        if ((Dev-Md5 $s $bakFile) -ne $script:HomeOrigMd5) { Err 'backup of the original Ticwear home is damaged - nothing changed'; return $false }
    }
    DevSh $s "rm -rf $tmp; mkdir -p $tmp" | Out-Null
    Say '  copying the patch to the watch ...'
    if ((AdbS $s @('push', $dex, "$tmp/classes.dex")).Code -ne 0) { Err 'could not copy the patch to the watch'; return $false }
    if ((Dev-Md5 $s "$tmp/classes.dex") -ne $want) { Err 'the patch arrived damaged on the watch - nothing changed'; return $false }
    Say '  compiling it on the watch (takes a few minutes, keep the watch on the charger) ...'
    DevSh $s ("cd $tmp && dex2oat --runtime-arg -Xms64m --runtime-arg -Xmx512m --boot-image=/system/framework/boot.art " +
        "--dex-file=$tmp/classes.dex --dex-location=$($script:HomeApk) --oat-file=$tmp/MobvoiWearHome.odex --android-root=/system " +
        "--instruction-set=arm --instruction-set-features=div --include-patch-information --runtime-arg -Xnorelocate " +
        "--no-include-debug-symbols --compile-pic") | Out-Null
    if ((DevSh $s "[ -s $tmp/MobvoiWearHome.odex ] && echo ODEX_OK") -notmatch 'ODEX_OK') { Err 'compiling on the watch failed - nothing changed'; DevSh $s "rm -rf $tmp" | Out-Null; return $false }
    if (-not (Swap-HomeOdex $s "$tmp/MobvoiWearHome.odex")) { Err 'could not install the patched Ticwear home'; return $false }
    $newMd5 = Dev-Md5 $s $script:HomeOdex
    DevSh $s "echo $want $newMd5 > $($script:HomeBak)/applied; rm -rf $tmp" | Out-Null
    Restart-Home $s
    Ok 'Ticwear home patched: swipe right on the watch face or say "OK Tico" to open Sonora'
    return $true
}
