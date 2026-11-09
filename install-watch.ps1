# ticwatch2-revive - install / update the revive apps on a Ticwatch 2 and disable the log hogs.
# Windows: double-click install-watch.bat, or run in PowerShell:  .\install-watch.ps1 [options]
# Options use the same names as the Mac/Linux script (--addr, --restore, ...).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'lib\common.ps1')

function Usage {
@'
Usage: install-watch.ps1 [options]

Installs or updates the watch apps listed in manifest.tsv and disables the system apps
listed in system-apps.tsv. Safe to run again at any time (e.g. after a factory reset,
or after new versions were pushed to the repository): apps that are already current
are left alone.

  --addr IP:PORT   connect to the watch over Wi-Fi first (e.g. 192.168.1.50:5555)
  --no-disable     only install/update the apps, do not touch system apps
  --no-home-patch  do not patch Ticwear home (voice launches then keep opening Tico)
  --restore        undo: re-enable the disabled system apps, put the original Ticwear home back
                   and remove the Install on Watch receiver (restarts the watch)
  --force          if an app is installed with a different signing key, uninstall it first
                   (erases that app's data)
  --offline        do not look for newer files online (no git pull / download)
  --yes            answer "yes" to prompts (e.g. downloading platform-tools)
  --dry-run        show what would be done, change nothing
  -h, --help       this text
'@ | Write-Host
}

$script:Addr = ''; $noDisable = $false; $noHome = $false; $restore = $false; $script:Force = $false
$script:Offline = $false; $script:AssumeYes = $false; $script:DryRun = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ($args[$i]) {
        '^-{1,2}addr$'       { $i++; $script:Addr = [string]$args[$i]; if (-not $script:Addr) { Die '--addr needs IP:PORT' } }
        '^-{1,2}no-?disable$' { $noDisable = $true }
        '^-{1,2}no-?home-?patch$' { $noHome = $true }
        '^-{1,2}restore$'    { $restore = $true }
        '^-{1,2}force$'      { $script:Force = $true }
        '^-{1,2}offline$'    { $script:Offline = $true }
        '^-{1,2}(yes|y)$'    { $script:AssumeYes = $true }
        '^-{1,2}dry-?run$'   { $script:DryRun = $true }
        '^(-h|--help|-help|/\?)$' { Usage; exit 0 }
        default { Usage; Die "unknown option: $($args[$i])" }
    }
}

Init-Paths $here
Say 'ticwatch2-revive - watch installer'

Step 'Looking for newer app versions'
Sync-Repo
if ($script:ScriptsUpdated) {
    Say '  the installer itself was updated - restarting it'
    $exe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args --offline
    exit $LASTEXITCODE
}

Step 'Android Debug Bridge'
Find-Adb; Ok "adb: $($script:AdbExe)"
Adb @('start-server') | Out-Null

Step 'Finding the watch'
Pick-Watch
StayAwake $script:Watch $true
try {
    if ($restore) {
        Step 'Re-enabling system apps'
        Apply-SysApps $script:Watch 'enable'
        Step 'Putting the original Ticwear home back'
        $null = Home-Patch $script:Watch 'restore'
        Step 'Removing the Install on Watch receiver'
        $null = SysApps $script:Watch 'remove'
        if ($script:SysReboot) { $null = Reboot-Watch $script:Watch }
        Say ''; Say 'Done.'; exit 0
    }

    Step 'Installing apps'
    $okAll = Install-Target $script:Watch 'watch'

    Step 'Install on Watch receiver (system app)'
    if (-not (SysApps $script:Watch 'install')) { $okAll = $false }

    if (-not $noHome) {
        Step 'Voice button -> Sonora (Ticwear home patch)'
        if (-not (Home-Patch $script:Watch 'apply')) { $okAll = $false }
    }

    if (-not $noDisable) {
        Step 'Disabling unneeded system apps'
        Apply-SysApps $script:Watch 'disable'
    }

    if ($script:SysReboot) {
        Step 'Restarting the watch so the system app starts'
        if (Reboot-Watch $script:Watch) { if (-not (Check-SysApps $script:Watch)) { $okAll = $false } } else { $okAll = $false }
    }

    Step 'Finished'
    if ($okAll) { Ok 'all done' } else { Warn 'finished with errors - see messages above' }
    @'

  Next, on the watch (first time after a reset):
   * Settings > Apps (or the permission prompt): allow Microphone for Sonora and Maps, and Internet if asked.
   * Maps: optional Google key - see README > Maps. Without a key routing + search use OpenStreetMap services.
   * Sonora: with Xiaozhi, open it once for a pairing code; with Home Assistant see docs/home-assistant.md.
  Re-run this script any time to pick up new versions. Undo the system-app and home changes with --restore.
'@ | Write-Host
    if (-not $okAll) { exit 1 }
} finally {
    StayAwake $script:Watch $false
}
