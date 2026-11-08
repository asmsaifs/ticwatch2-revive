#!/usr/bin/env bash
# ticwatch2-revive – install / update the revive apps on a Ticwatch 2 and disable the log hogs.
# Works on macOS, Linux, WSL and Git-Bash. Windows users: double-click install-watch.bat instead.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

usage() { cat <<USAGE
Usage: ./install-watch.sh [options]

Installs or updates the watch apps listed in manifest.tsv and disables the system apps
listed in system-apps.tsv. Safe to run again at any time (e.g. after a factory reset,
or after new versions were pushed to the repository): apps that are already current
are left alone.

  --addr IP:PORT   connect to the watch over Wi-Fi first (e.g. 192.168.1.50:5555)
  --no-disable     only install/update the apps, do not touch system apps
  --restore        undo: re-enable the system apps that were disabled by this script
  --force          if an app is installed with a different signing key, uninstall it first
                   (erases that app's data)
  --offline        do not look for newer files online (no git pull / download)
  --yes            answer "yes" to prompts (e.g. downloading platform-tools)
  --dry-run        show what would be done, change nothing
  -h, --help       this text
USAGE
}

ADDR=; NO_DISABLE=0; RESTORE=0; FORCE=0; OFFLINE=0; ASSUME_YES=0; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --addr) ADDR=${2:-}; [ -n "$ADDR" ] || die "--addr needs IP:PORT"; shift ;;
    --no-disable) NO_DISABLE=1 ;;
    --restore) RESTORE=1 ;;
    --force) FORCE=1 ;;
    --offline) OFFLINE=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown option: $1" ;;
  esac
  shift
done

init_paths "$HERE"
say "ticwatch2-revive · watch installer"

step "Looking for newer app versions"
sync_repo

step "Android Debug Bridge"
find_adb; ok "adb: $ADB"
"$ADB" start-server >/dev/null 2>&1

step "Finding the watch"
pick_watch
trap 'stay_awake_off "$WATCH"' EXIT
stay_awake_on "$WATCH"

if [ "$RESTORE" = 1 ]; then
  step "Re-enabling system apps"
  apply_sysapps "$WATCH" enable
  say; say "Done."; exit 0
fi

step "Installing apps"
RC=0
install_target "$WATCH" watch || RC=1

if [ "$NO_DISABLE" = 0 ]; then
  step "Disabling unneeded system apps"
  apply_sysapps "$WATCH" disable
fi

step "Finished"
if [ "$RC" = 0 ]; then ok "all done"; else warn "finished with errors – see messages above"; fi
cat <<NEXT

  Next, on the watch (first time after a reset):
   • Settings › Apps (or the permission prompt): allow Microphone for Xiaozhi and Maps, and Internet if asked.
   • Maps: optional Google key – see README › Maps. Without a key routing + search use OpenStreetMap services.
   • Xiaozhi: open it once; it shows a pairing code to enter in your Xiaozhi account.
  Re-run this script any time to pick up new versions. Undo the system-app changes with --restore.
NEXT
exit $RC
