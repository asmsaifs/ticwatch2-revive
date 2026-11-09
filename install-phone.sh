#!/usr/bin/env bash
# ticwatch2-revive – install / update the phone-side app(s) on an Android phone.
# Works on macOS, Linux, WSL and Git-Bash. Windows users: double-click install-phone.bat instead.
set -u
ORIG_ARGS=("$@")
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

usage() { cat <<USAGE
Usage: ./install-phone.sh [options]

Installs or updates the phone apps listed in manifest.tsv (target "phone") on an Android
phone connected with USB debugging or Wireless debugging. Safe to re-run: apps that are
already current are left alone.

  --serial ID          use this adb device (see: adb devices) when several are attached
  --pair HOST:PORT CODE  pair with a phone over Wireless debugging first (Android 11+),
                       using the pairing address and 6-digit code shown on the phone
  --connect HOST:PORT  connect to a phone over Wireless debugging (the main address, not the pairing one)
  --force              if an app is installed with a different signing key, uninstall it first
  --offline            do not look for newer files online (no git pull / download)
  --yes                answer "yes" to prompts
  --dry-run            show what would be done, change nothing
  -h, --help           this text
USAGE
}

SERIAL=; PAIR_ADDR=; PAIR_CODE=; CONNECT=; FORCE=0; OFFLINE=0; ASSUME_YES=0; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --serial) SERIAL=${2:-}; [ -n "$SERIAL" ] || die "--serial needs a device id"; shift ;;
    --pair) PAIR_ADDR=${2:-}; PAIR_CODE=${3:-}; [ -n "$PAIR_ADDR" ] && [ -n "$PAIR_CODE" ] || die "--pair needs HOST:PORT and the 6-digit CODE"; shift 2 ;;
    --connect) CONNECT=${2:-}; [ -n "$CONNECT" ] || die "--connect needs HOST:PORT"; shift ;;
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
say "ticwatch2-revive · phone installer"

step "Looking for newer app versions"
sync_repo
if [ "${SCRIPTS_UPDATED:-0}" = 1 ]; then
  say "  the installer itself was updated – restarting it"
  exec bash "$0" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"} --offline
fi

step "Android Debug Bridge"
find_adb; ok "adb: $ADB"
"$ADB" start-server >/dev/null 2>&1

if [ -n "$PAIR_ADDR" ]; then
  step "Pairing"
  "$ADB" pair "$PAIR_ADDR" "$PAIR_CODE" </dev/null 2>&1 | tr -d '\r' | sed 's/^/    /'
fi
if [ -n "$CONNECT" ]; then "$ADB" connect "$CONNECT" </dev/null 2>&1 | tr -d '\r' | sed 's/^/    /'; sleep 1; fi

step "Finding the phone"
PHONE=
if [ -n "$SERIAL" ]; then PHONE=$SERIAL
else
  CANDS=()
  for s in $(online_serials); do is_watch "$s" || CANDS+=("$s"); done
  if [ "${#CANDS[@]}" -eq 1 ]; then PHONE=${CANDS[0]}
  elif [ "${#CANDS[@]}" -gt 1 ]; then
    say "  several phones attached:"; i=1
    for s in "${CANDS[@]}"; do say "    $i) $s  ($(dev_sh "$s" getprop ro.product.model))"; i=$((i+1)); done
    n=$(ask "Which one? [1-${#CANDS[@]}]") || die "several devices attached: pass --serial ID"
    PHONE=${CANDS[$((n-1))]:-}; [ -n "$PHONE" ] || die "invalid choice"
  fi
fi
if [ -z "$PHONE" ]; then
  "$ADB" devices | awk 'NR>1 && $2!="device" && NF {print "    " $1 " is \"" $2 "\" (unauthorized: unlock the phone and accept the USB-debugging prompt)"}'
  die "no phone found. Enable Developer options › USB debugging (or Wireless debugging and use --pair / --connect), then re-run."
fi
ok "phone: $PHONE ($(dev_sh "$PHONE" getprop ro.product.model), Android $(dev_sh "$PHONE" getprop ro.build.version.release))"
[ "$(abi_class "$PHONE")" = 64 ] && ok "64-bit-only phone: using the arm64 builds of the Mobvoi apps"

step "Installing apps"
RC=0
install_target "$PHONE" phone || RC=1

# Best effort: grant what the app needs so it works the first time.
if [ "$RC" = 0 ] && [ "$DRY_RUN" = 0 ]; then
  PKG=org.xzwatch.bridge.phone
  if [ -n "$(installed_path "$PHONE" "$PKG")" ]; then
    step "Granting permissions to Install on Watch"
    for perm in android.permission.POST_NOTIFICATIONS android.permission.BLUETOOTH_CONNECT; do
      dev_sh "$PHONE" pm grant "$PKG" "$perm" >/dev/null 2>&1 && ok "${perm##*.}" || say "  (could not grant ${perm##*.} – it will ask on first use)"
    done
    dev_sh "$PHONE" appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1 && ok "All-files access" || say "  (could not grant All-files access – allow it in Settings › Apps › Special access)"
  fi
fi

step "Finished"
if [ "$RC" = 0 ]; then ok "all done"; else warn "finished with errors – see messages above"; fi
cat <<NEXT

  "Install on Watch" now appears when you open an .apk file (Open with…).
  Re-run this script any time to pick up new versions.
NEXT
exit $RC
