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
    if git -C "$ROOT" pull --ff-only -q 2>/dev/null; then ok "repository updated (git pull)"; return 0; fi
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

# Run every manifest row for one target ("watch"/"phone") against a device.
install_target() { # serial target
  local s=$1 want=$2 target pkg file md5 name apk rc=0 n=0
  while IFS=$'\t' read -r target pkg file md5 name; do
    case "$target" in ''|\#*) continue ;; esac
    [ "$target" = "$want" ] || continue
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
