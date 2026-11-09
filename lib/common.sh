# shellcheck shell=bash
# Shared helpers for install-watch.sh / install-phone.sh (macOS, Linux, WSL, Git-Bash).
# Sourced, never executed directly.

# ----------------------------------------------------------------- config
# Used only when the script is not inside a git clone that has an "origin" remote.
# Change it if you fork the repository, or export TICWATCH2_REVIVE_RAW to override.
DEFAULT_RAW="https://raw.githubusercontent.com/asmsaifs/ticwatch2-revive/main"
PLATFORM_TOOLS_BASE="https://dl.google.com/android/repository/platform-tools-latest"

# ----------------------------------------------------------------- output
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_CYN=$'\033[36m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_CYN=; C_DIM=; C_OFF=
fi
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s== %s%s\n' "$C_CYN" "$*" "$C_OFF"; }
ok()   { printf '  %s✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YEL" "$C_OFF" "$*"; }
err()  { printf '  %s✗%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()  { err "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Ask a yes/no question (default no). --yes answers yes. Non-interactive: no.
confirm() {
  [ "${ASSUME_YES:-0}" = 1 ] && return 0
  [ -r /dev/tty ] || return 1
  local a; printf '  %s [y/N] ' "$1" > /dev/tty; read -r a < /dev/tty || return 1
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
# Read a line from the terminal.
ask() { local a; [ -r /dev/tty ] || return 1; printf '  %s ' "$1" > /dev/tty; read -r a < /dev/tty || return 1; printf '%s' "$a"; }

# ----------------------------------------------------------------- files
md5_of() {
  if have md5sum; then md5sum "$1" | awk '{print $1}'
  elif have md5; then md5 -q "$1"
  else openssl md5 "$1" | awk '{print $NF}'; fi
}
http_get() { # url out
  if have curl; then curl -fsSL --retry 2 --connect-timeout 15 -o "$2" "$1"
  elif have wget; then wget -q -T 15 -O "$2" "$1"
  else return 1; fi
}

# ROOT = repo folder. MANIFEST/SYSAPPS may be redirected to .cache after an online sync.
init_paths() { # $1 = dir of the calling script
  ROOT="$1"
  CACHE="$ROOT/.cache"
  MANIFEST="$ROOT/manifest.tsv"
  SYSAPPS="$ROOT/system-apps.tsv"
  [ -f "$MANIFEST" ] || die "manifest.tsv not found next to the script – run it from the repository folder"
}

raw_base() {
  if [ -n "${TICWATCH2_REVIVE_RAW:-}" ]; then printf '%s' "$TICWATCH2_REVIVE_RAW"; return; fi
  if [ -d "$ROOT/.git" ] && have git; then
    local url br; url=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
    br=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
    case "$url" in
      https://github.com/*) url=${url#https://github.com/} ;;
      git@github.com:*)     url=${url#git@github.com:} ;;
      *) url= ;;
    esac
    url=${url%.git}
    if [ -n "$url" ]; then printf 'https://raw.githubusercontent.com/%s/%s' "$url" "$br"; return; fi
  fi
  printf '%s' "$DEFAULT_RAW"
}

# Pick up new/changed apps pushed to the repository since this copy was made.
sync_repo() {
  [ "${OFFLINE:-0}" = 1 ] && { say "  offline mode: using the files in this folder"; return 0; }
  if [ -d "$ROOT/.git" ] && have git; then
    local before; before=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
    if git -C "$ROOT" pull --ff-only -q 2>/dev/null; then
      ok "repository updated (git pull)"
      # The installer scripts themselves changed: the caller restarts so the new code runs now.
      if [ -n "$before" ] && ! git -C "$ROOT" diff --quiet "$before" HEAD -- '*.sh' lib 2>/dev/null; then SCRIPTS_UPDATED=1; fi
      return 0
    fi
    warn "git pull did not work (local changes?) – trying a plain download instead"
  fi
  local raw; raw=$(raw_base)
  if [ -z "$raw" ]; then warn "no repository URL known (edit DEFAULT_RAW in lib/common.sh) – using local files"; return 0; fi
  mkdir -p "$CACHE"
  if ! http_get "$raw/manifest.tsv" "$CACHE/manifest.tsv"; then warn "cannot reach $raw – using the files in this folder"; return 0; fi
  http_get "$raw/system-apps.tsv" "$CACHE/system-apps.tsv" 2>/dev/null && SYSAPPS="$CACHE/system-apps.tsv"
  MANIFEST="$CACHE/manifest.tsv"
  local target pkg file md5 name n=0
  while IFS=$'\t' read -r target pkg file md5 name; do
    case "$target" in ''|\#*) continue ;; esac
    if [ -f "$ROOT/$file" ] && [ "$(md5_of "$ROOT/$file")" = "$md5" ]; then continue; fi
    if [ -f "$CACHE/$file" ] && [ "$(md5_of "$CACHE/$file")" = "$md5" ]; then continue; fi
    mkdir -p "$(dirname "$CACHE/$file")"
    say "  downloading newer $name ($file)"
    if http_get "$raw/$file" "$CACHE/$file" && [ "$(md5_of "$CACHE/$file")" = "$md5" ]; then n=$((n+1))
    else rm -f "$CACHE/$file"; warn "download of $file failed or does not match the manifest – keeping the local copy"; fi
  done < "$MANIFEST"
  ok "online sync done ($n file(s) downloaded)"
}

# Local path of the APK to install: a verified download wins over the checked-in copy.
apk_for() { # file md5
  if [ -f "$CACHE/$1" ] && [ "$(md5_of "$CACHE/$1")" = "$2" ]; then printf '%s' "$CACHE/$1"; else printf '%s' "$ROOT/$1"; fi
}

# ----------------------------------------------------------------- adb
find_adb() {
  ADB=
  if [ -n "${ADB_BIN:-}" ] && [ -x "$ADB_BIN" ]; then ADB=$ADB_BIN
  elif have adb; then ADB=$(command -v adb)
  elif [ -x "$ROOT/.platform-tools/platform-tools/adb" ]; then ADB="$ROOT/.platform-tools/platform-tools/adb"
  elif [ -n "${ANDROID_HOME:-}" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ]; then ADB="$ANDROID_HOME/platform-tools/adb"
  elif [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then ADB="$HOME/Library/Android/sdk/platform-tools/adb"
  elif [ -x "$HOME/Android/Sdk/platform-tools/adb" ]; then ADB="$HOME/Android/Sdk/platform-tools/adb"
  fi
  [ -n "$ADB" ] && return 0
  warn "adb (Android platform-tools) not found"
  local os
  case "$(uname -s)" in Darwin) os=darwin ;; Linux) os=linux ;; *) die "install Android platform-tools from https://developer.android.com/tools/releases/platform-tools and re-run" ;; esac
  have unzip || die "unzip is needed to unpack platform-tools – install it, or install platform-tools yourself"
  if confirm "Download Google's official platform-tools (≈15 MB) into $ROOT/.platform-tools ?"; then
    mkdir -p "$ROOT/.platform-tools"
    http_get "$PLATFORM_TOOLS_BASE-$os.zip" "$ROOT/.platform-tools/pt.zip" || die "download failed"
    unzip -q -o "$ROOT/.platform-tools/pt.zip" -d "$ROOT/.platform-tools" && rm -f "$ROOT/.platform-tools/pt.zip"
    ADB="$ROOT/.platform-tools/platform-tools/adb"
    [ -x "$ADB" ] || die "platform-tools unpacked but adb not found"
  else
    die "adb is required. Install platform-tools (https://developer.android.com/tools/releases/platform-tools) and re-run."
  fi
}

# adb must never read our stdin: inside "while read" loops it would swallow the rest of the file.
adb_s() { local s=$1; shift; "$ADB" -s "$s" "$@" </dev/null; }
# Run a shell command on the device; strips the CRs adb adds.
dev_sh() { local s=$1; shift; "$ADB" -s "$s" shell "$@" 2>&1 </dev/null | tr -d '\r'; }

# Serials currently in state "device"
online_serials() { "$ADB" devices </dev/null | awk 'NR>1 && $2=="device" {print $1}'; }
product_of() { dev_sh "$1" getprop ro.product.device | tr -d '\n'; }
is_watch() { [ "$(product_of "$1")" = "mercury" ]; }

# ----------------------------------------------------------------- apps
installed_path() { dev_sh "$1" pm path "$2" | grep -m1 '^package:' | cut -d: -f2; }
installed_md5() { # serial pkg  -> md5 or empty
  local p; p=$(installed_path "$1" "$2"); [ -n "$p" ] || return 0
  dev_sh "$1" "md5sum $p 2>/dev/null || md5 $p" | awk 'NF {print $1; exit}'
}

# install_app serial apk pkg name
install_app() {
  local s=$1 apk=$2 pkg=$3 name=$4 have want out
  want=$(md5_of "$apk"); have=$(installed_md5 "$s" "$pkg")
  if [ -n "$have" ] && [ "$have" = "$want" ]; then ok "$name is up to date"; return 0; fi
  if [ -n "$have" ]; then say "  updating $name …"; else say "  installing $name …"; fi
  [ "${DRY_RUN:-0}" = 1 ] && { say "  (dry run) adb install -r $apk"; return 0; }
  out=$(adb_s "$s" install -r "$apk" 2>&1 | tr -d '\r')
  case "$out" in
    *Success*) ok "$name installed" ;;
    *INSTALL_FAILED_UPDATE_INCOMPATIBLE*|*INSTALL_FAILED_SIGNATURE*)
      if [ "${FORCE:-0}" = 1 ]; then
        warn "$name was signed with a different key – uninstalling it first (its data is erased)"
        adb_s "$s" uninstall "$pkg" >/dev/null 2>&1
        out=$(adb_s "$s" install "$apk" 2>&1 | tr -d '\r')
        case "$out" in *Success*) ok "$name installed" ;; *) err "$name: $out"; return 1 ;; esac
      else
        err "$name is installed with a different signing key. Re-run with --force to replace it (this erases the app's data)."; return 1
      fi ;;
    *INSTALL_FAILED_DEPRECATED_SDK_VERSION*|*"older"*SDK*|*"target SDK"*)
      out=$(adb_s "$s" install -r --bypass-low-target-sdk-block "$apk" 2>&1 | tr -d '\r')
      case "$out" in *Success*) ok "$name installed (low-target-SDK block bypassed)" ;; *) err "$name: $out"; return 1 ;; esac ;;
    *) err "$name: ${out##*$'\n'}"; return 1 ;;
  esac
}

# "32" if the device can run 32-bit ARM code (armeabi-v7a), "64" if it is a 64-bit-only phone
# (newer Snapdragon / Tensor / Dimensity chips). The Mobvoi apps only carry 32-bit native libraries,
# so 64-bit-only phones get the "-arm64" builds with those libraries stripped out.
abi_class() { # serial
  local l32 l
  l32=$(dev_sh "$1" getprop ro.product.cpu.abilist32 | tr -d '\r\n ')
  l=$(dev_sh "$1" getprop ro.product.cpu.abilist | tr -d '\r\n ')
  case ",$l32,$l," in *,armeabi-v7a,*|*,armeabi,*) echo 32; return ;; esac
  if [ -n "$l" ]; then echo 64; else echo 32; fi
}

# Run every manifest row for one target ("watch"/"phone") against a device.
# Rows with target "<target>32" / "<target>64" are only used on devices of that ABI class.
install_target() { # serial target
  local s=$1 want=$2 target pkg file md5 name apk rc=0 n=0 cls
  cls=$(abi_class "$s")
  while IFS=$'\t' read -r target pkg file md5 name; do
    case "$target" in ''|\#*) continue ;; esac
    [ "$target" = "$want" ] || [ "$target" = "$want$cls" ] || continue
    apk=$(apk_for "$file" "$md5")
    if [ ! -f "$apk" ]; then err "$file is listed in the manifest but missing"; rc=1; continue; fi
    install_app "$s" "$apk" "$pkg" "$name" || rc=1; n=$((n+1))
  done < "$MANIFEST"
  [ "$n" -gt 0 ] || warn "the manifest lists no $want apps"
  return $rc
}

# Keep the screen on while charging so a Wi-Fi adb link does not drop mid-install (best effort).
stay_awake_on()  { dev_sh "$1" svc power stayon true >/dev/null 2>&1 || true; }
stay_awake_off() { dev_sh "$1" svc power stayon false >/dev/null 2>&1 || true; }

# Apply (disable) or undo (enable) the system-app list.
apply_sysapps() { # serial disable|enable
  local s=$1 mode=$2 pkg on why present state out n=0
  [ -f "$SYSAPPS" ] || { warn "no system-apps.tsv"; return 0; }
  present=$(dev_sh "$s" pm list packages)
  state=$(dev_sh "$s" pm list packages -d)
  while IFS=$'\t' read -r pkg on why; do
    case "$pkg" in ''|\#*) continue ;; esac
    [ "$on" = yes ] || continue
    if ! printf '%s\n' "$present" | grep -qx "package:$pkg"; then say "  $pkg: not on this watch, skipped"; continue; fi
    if [ "$mode" = disable ]; then
      if printf '%s\n' "$state" | grep -qx "package:$pkg"; then ok "$pkg already disabled"; continue; fi
    else
      if ! printf '%s\n' "$state" | grep -qx "package:$pkg"; then ok "$pkg already enabled"; continue; fi
    fi
    [ "${DRY_RUN:-0}" = 1 ] && { say "  (dry run) pm $mode $pkg"; continue; }
    out=$(dev_sh "$s" pm "$mode" "$pkg")
    case "$out" in
      *"new state"*) if [ "$mode" = disable ]; then ok "$pkg disabled – $why"; else ok "$pkg enabled"; fi; n=$((n+1)) ;;
      *)  # some builds need root for this: try it once
          if [ -z "${TRIED_ROOT:-}" ]; then
            TRIED_ROOT=1; adb_s "$s" root >/dev/null 2>&1; sleep 3; "$ADB" connect "$s" >/dev/null 2>&1; sleep 1
            out=$(dev_sh "$s" pm "$mode" "$pkg")
            case "$out" in *"new state"*) ok "$pkg ${mode}d (needed adb root)"; n=$((n+1)); continue ;; esac
          fi
          err "$pkg: ${out%%$'\n'*}" ;;
    esac
  done < "$SYSAPPS"
  return 0
}

# Find the watch (model "mercury") among the attached adb devices, offering to connect over Wi-Fi.
pick_watch() { # sets WATCH
  WATCH=
  local s tries=0 addr
  if [ -n "${ADDR:-}" ]; then "$ADB" connect "$ADDR" >/dev/null 2>&1; sleep 1; fi
  while :; do
    for s in $(online_serials); do
      if is_watch "$s"; then WATCH=$s; break 2; fi
    done
    tries=$((tries+1))
    "$ADB" devices | awk 'NR>1 && $2!="device" && NF {print "    " $1 " is \"" $2 "\" (offline/unauthorized: toggle ADB debugging on the watch, accept the prompt)"}'
    [ "$tries" -ge 3 ] && die "no Ticwatch 2 found. Enable ADB debugging on the watch and connect it (see README › Connect the watch)."
    say "  No Ticwatch 2 found yet."
    say "  On the watch: Settings › About › tap Build number 7× › Developer options › ADB debugging + Debug over Wi-Fi."
    addr=$(ask "Watch address as IP:PORT (shown in Developer options; empty = retry USB/cradle):") || die "no watch found (non-interactive: pass --addr IP:PORT)"
    [ -n "$addr" ] && { "$ADB" connect "$addr" 2>&1 | tr -d '\r' | sed 's/^/    /'; sleep 1; }
  done
  ok "watch found: $WATCH"
}

# ----------------------------------------------------------------- Ticwear home patch
# Makes every voice launch of the watch (swipe right on the watch face, "OK Tico", the wrist gesture)
# open Sonora instead of Tico; if Sonora is missing, Tico still opens. Ticwear home is a platform-signed
# system app, so its APK cannot be re-signed: only its compiled code (the .odex) is replaced. The
# patched classes.dex is compiled ON the watch by the watch's own dex2oat against its own boot image.
# Needs adb root (the userdebug ROM from the README has it). Built for Tic_4.13.0_intl_a1 only: on any
# other Ticwear home the step is skipped. The original odex is kept in /system/xzpatch (survives a
# factory reset); --restore puts it back.
HOME_PKG=com.mobvoi.ticwear.home
HOME_ODEX=/system/priv-app/MobvoiWearHome/arm/MobvoiWearHome.odex
HOME_APK=/system/priv-app/MobvoiWearHome/MobvoiWearHome.apk
HOME_ORIG_MD5=1fd6479ec9b71dc3108e2b594302cc2a   # stock odex of Tic_4.13.0_intl_a1
HOME_BAK=/system/xzpatch
HOME_TMP=/data/local/tmp/xzpatch

# 0 when adbd on the device runs as root; restarts adbd as root once if needed.
dev_root() { # serial
  local s=$1 i
  dev_sh "$s" id | grep -q 'uid=0' && return 0
  adb_s "$s" root >/dev/null 2>&1
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 2
    case "$s" in *:*) "$ADB" connect "$s" >/dev/null 2>&1 </dev/null ;; esac
    dev_sh "$s" id | grep -q 'uid=0' && return 0
  done
  return 1
}

dev_md5() { dev_sh "$1" "md5 $2 2>/dev/null || md5sum $2 2>/dev/null" | awk 'NF {print $1; exit}'; }

restart_home() {
  dev_sh "$1" "am force-stop $HOME_PKG; sleep 2; am start -a android.intent.action.MAIN -c android.intent.category.HOME" >/dev/null 2>&1 || true
}

# Swap an odex already on the watch ($2) into place, atomically (same file system rename).
swap_home_odex() { # serial src
  dev_sh "$1" "cp $2 $HOME_ODEX.new && chmod 644 $HOME_ODEX.new && chown root:root $HOME_ODEX.new && chcon u:object_r:system_file:s0 $HOME_ODEX.new && mv $HOME_ODEX.new $HOME_ODEX && sync && echo SWAP_OK"
}

home_patch() { # serial apply|restore
  local s=$1 mode=$2 row file want dex cur mdex modex bak out
  if ! dev_root "$s"; then
    warn "skipped: needs adb root (the userdebug ROM in README › Flash the old ROM has it)"; return 0
  fi
  cur=$(dev_md5 "$s" "$HOME_ODEX")
  [ -n "$cur" ] || { warn "skipped: Ticwear home not found on this watch"; return 0; }
  out=$(dev_sh "$s" "cat $HOME_BAK/applied 2>/dev/null"); mdex=$(printf '%s\n' "$out" | awk 'NF {print $1; exit}'); modex=$(printf '%s\n' "$out" | awk 'NF {print $2; exit}')
  bak=$(dev_md5 "$s" "$HOME_BAK/MobvoiWearHome.odex.orig")

  if [ "$mode" = restore ]; then
    if [ "$cur" = "$HOME_ORIG_MD5" ]; then ok "Ticwear home is the original"; return 0; fi
    [ "$bak" = "$HOME_ORIG_MD5" ] || { err "no backup of the original Ticwear home on the watch – reflash the ROM to undo"; return 1; }
    [ "${DRY_RUN:-0}" = 1 ] && { say "  (dry run) restore $HOME_ODEX from $HOME_BAK"; return 0; }
    adb_s "$s" remount >/dev/null 2>&1
    case "$(swap_home_odex "$s" "$HOME_BAK/MobvoiWearHome.odex.orig")" in *SWAP_OK*) ;; *) err "could not restore the original Ticwear home"; return 1 ;; esac
    dev_sh "$s" "rm -f $HOME_BAK/applied" >/dev/null
    restart_home "$s"; ok "original Ticwear home restored (voice opens Tico again)"; return 0
  fi

  row=$(awk -F'\t' '$1=="watch-home" {print; exit}' "$MANIFEST")
  [ -n "$row" ] || { warn "the manifest lists no home patch"; return 0; }
  file=$(printf '%s' "$row" | cut -f3); want=$(printf '%s' "$row" | cut -f4)
  dex=$(apk_for "$file" "$want")
  [ -f "$dex" ] || { err "$file is listed in the manifest but missing"; return 1; }

  if [ "$cur" = "$HOME_ORIG_MD5" ]; then say "  patching Ticwear home …"
  elif [ -n "$mdex" ] && [ "$modex" = "$cur" ]; then
    if [ "$mdex" = "$want" ]; then ok "Ticwear home patch is up to date"; return 0; fi
    [ "$bak" = "$HOME_ORIG_MD5" ] || { err "patched Ticwear home without a backup of the original – skipped"; return 1; }
    say "  updating the Ticwear home patch …"
  else
    warn "skipped: this watch's Ticwear home is not the Tic_4.13.0_intl_a1 one the patch was made for"; return 0
  fi
  [ "${DRY_RUN:-0}" = 1 ] && { say "  (dry run) compile $file on the watch and replace $HOME_ODEX"; return 0; }

  out=$(adb_s "$s" remount 2>&1 | tr -d '\r')
  case "$out" in *succeeded*) ;; *) err "cannot make /system writable: $out"; return 1 ;; esac
  if [ "$bak" != "$HOME_ORIG_MD5" ]; then
    out=$(dev_sh "$s" "mkdir -p $HOME_BAK && cp $HOME_ODEX $HOME_BAK/MobvoiWearHome.odex.orig && sync && echo BAK_OK")
    case "$out" in *BAK_OK*) ;; *) err "could not back up the original Ticwear home – nothing changed"; return 1 ;; esac
    [ "$(dev_md5 "$s" "$HOME_BAK/MobvoiWearHome.odex.orig")" = "$HOME_ORIG_MD5" ] || { err "backup of the original Ticwear home is damaged – nothing changed"; return 1; }
  fi
  dev_sh "$s" "rm -rf $HOME_TMP; mkdir -p $HOME_TMP" >/dev/null
  say "  copying the patch to the watch …"
  adb_s "$s" push "$dex" "$HOME_TMP/classes.dex" >/dev/null 2>&1 || { err "could not copy the patch to the watch"; return 1; }
  [ "$(dev_md5 "$s" "$HOME_TMP/classes.dex")" = "$want" ] || { err "the patch arrived damaged on the watch – nothing changed"; return 1; }
  say "  compiling it on the watch (takes a few minutes, keep the watch on the charger) …"
  dev_sh "$s" "cd $HOME_TMP && dex2oat --runtime-arg -Xms64m --runtime-arg -Xmx512m --boot-image=/system/framework/boot.art --dex-file=$HOME_TMP/classes.dex --dex-location=$HOME_APK --oat-file=$HOME_TMP/MobvoiWearHome.odex --android-root=/system --instruction-set=arm --instruction-set-features=div --include-patch-information --runtime-arg -Xnorelocate --no-include-debug-symbols --compile-pic" >/dev/null
  case "$(dev_sh "$s" "[ -s $HOME_TMP/MobvoiWearHome.odex ] && echo ODEX_OK")" in *ODEX_OK*) ;; *) err "compiling on the watch failed – nothing changed"; dev_sh "$s" "rm -rf $HOME_TMP" >/dev/null; return 1 ;; esac
  case "$(swap_home_odex "$s" "$HOME_TMP/MobvoiWearHome.odex")" in *SWAP_OK*) ;; *) err "could not install the patched Ticwear home"; return 1 ;; esac
  dev_sh "$s" "echo $want $(dev_md5 "$s" "$HOME_ODEX") > $HOME_BAK/applied; rm -rf $HOME_TMP" >/dev/null
  restart_home "$s"
  ok "Ticwear home patched: swipe right on the watch face or say \"OK Tico\" to open Sonora"
}

# ----------------------------------------------------------------- system apps on the watch
# Manifest rows with target "watch-system" are apps that need system privileges (e.g. the
# "Install on Watch" receiver, which installs APKs sent from the phone). They are copied to
# /system/priv-app/<Name>/<Name>.apk (Name = APK file name). Android only picks up /system apps
# while starting, so a change sets SYS_REBOOT=1 and the caller restarts the watch (reboot_watch).
SYS_TMP=/data/local/tmp/xzsys
SYS_REBOOT=0

sysapps() { # serial install|remove
  local s=$1 mode=$2 target pkg file md5 name apk base dir dest cur out p rc=0
  awk -F'\t' '$1=="watch-system" {f=1} END {exit !f}' "$MANIFEST" || { warn "the manifest lists no system apps"; return 0; }
  if ! dev_root "$s"; then
    warn "skipped: needs adb root (the userdebug ROM in README › Flash the old ROM has it)"; return 0
  fi
  while IFS=$'\t' read -r target pkg file md5 name; do
    [ "$target" = watch-system ] || continue
    base=$(basename "$file" .apk); dir=/system/priv-app/$base; dest=$dir/$base.apk
    cur=$(dev_md5 "$s" "$dest")
    if [ "$mode" = remove ]; then
      [ -n "$cur" ] || { ok "$name is not on the watch"; continue; }
      [ "${DRY_RUN:-0}" = 1 ] && { say "  (dry run) delete $dir"; continue; }
      out=$(adb_s "$s" remount 2>&1 | tr -d '\r')
      case "$out" in *succeeded*) ;; *) err "cannot make /system writable: $out"; rc=1; continue ;; esac
      case "$(dev_sh "$s" "rm -rf $dir && sync && echo RM_OK")" in
        *RM_OK*) ok "$name removed"; SYS_REBOOT=1 ;; *) err "could not remove $name"; rc=1 ;;
      esac
      continue
    fi
    if [ "$cur" = "$md5" ]; then ok "$name is up to date"; continue; fi
    apk=$(apk_for "$file" "$md5")
    [ -f "$apk" ] || { err "$file is listed in the manifest but missing"; rc=1; continue; }
    if [ -n "$cur" ]; then say "  updating $name …"; else say "  installing $name …"; fi
    [ "${DRY_RUN:-0}" = 1 ] && { say "  (dry run) copy $file to $dest"; continue; }
    out=$(adb_s "$s" remount 2>&1 | tr -d '\r')
    case "$out" in *succeeded*) ;; *) err "cannot make /system writable: $out"; rc=1; continue ;; esac
    # a normal (/data) install of the same package would shadow the system copy
    p=$(installed_path "$s" "$pkg"); case "$p" in /data/*) adb_s "$s" uninstall "$pkg" >/dev/null 2>&1 ;; esac
    dev_sh "$s" "rm -rf $SYS_TMP; mkdir -p $SYS_TMP" >/dev/null
    adb_s "$s" push "$apk" "$SYS_TMP/$base.apk" >/dev/null 2>&1 || { err "could not copy $name to the watch"; rc=1; continue; }
    [ "$(dev_md5 "$s" "$SYS_TMP/$base.apk")" = "$md5" ] || { err "$name arrived damaged on the watch – nothing changed"; rc=1; continue; }
    out=$(dev_sh "$s" "mkdir -p $dir && chmod 755 $dir && chcon u:object_r:system_file:s0 $dir && cp $SYS_TMP/$base.apk $dest.new && chmod 644 $dest.new && chown root:root $dest.new && chcon u:object_r:system_file:s0 $dest.new && mv $dest.new $dest && rm -rf $SYS_TMP && sync && echo SYS_OK")
    case "$out" in *SYS_OK*) ok "$name copied (active after the watch restarts)"; SYS_REBOOT=1 ;; *) err "could not install $name"; rc=1 ;; esac
  done < "$MANIFEST"
  return $rc
}

# Restart the watch and wait (up to ~5 min) until it is back.
reboot_watch() { # serial
  local s=$1 i
  [ "${DRY_RUN:-0}" = 1 ] && { say "  (dry run) restart the watch"; return 0; }
  say "  restarting the watch (takes about a minute) …"
  stay_awake_off "$s"
  adb_s "$s" reboot >/dev/null 2>&1
  sleep 15
  for i in $(seq 1 60); do
    case "$s" in *:*) "$ADB" connect "$s" >/dev/null 2>&1 </dev/null ;; esac
    if [ "$(dev_sh "$s" getprop sys.boot_completed 2>/dev/null | tr -d '\n ')" = 1 ]; then
      sleep 10   # adbd restarts once more right after boot; let it settle
      case "$s" in *:*) "$ADB" connect "$s" >/dev/null 2>&1 </dev/null ;; esac
      ok "watch restarted"; stay_awake_on "$s"; return 0
    fi
    sleep 5
  done
  warn "the watch did not come back within 5 minutes – it finishes starting on its own; run this script again to check"
  return 1
}

# After the restart: every system app must now run from /system/priv-app.
check_sysapps() { # serial
  local s=$1 target pkg file md5 name p rc=0
  while IFS=$'\t' read -r target pkg file md5 name; do
    [ "$target" = watch-system ] || continue
    p=$(installed_path "$s" "$pkg")
    case "$p" in /system/priv-app/*) ok "$name is active" ;; *) err "$name is not active after the restart (${p:-not installed})"; rc=1 ;; esac
  done < "$MANIFEST"
  return $rc
}
