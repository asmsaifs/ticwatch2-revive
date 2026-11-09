#!/usr/bin/env bash
# Maintainer helper: build the "-arm64" variant of an APK for 64-bit-only phones.
#
# Newer phones (e.g. Snapdragon 7 Gen 3 / 8 Gen 3+, Tensor G3+, Dimensity 9300+) no longer run 32-bit
# ARM code. The Mobvoi companion and store only ship armeabi-v7a native libraries, so Android refuses
# them there with INSTALL_FAILED_NO_MATCHING_ABIS. The libraries are only used by optional parts
# (phone-side voice/hotword, Baidu/Sogou maps, Weibo, UnionPay) and the apps load them defensively,
# so a copy without lib/ installs and runs as a 64-bit app.
#
# Usage: tools/make-arm64-variant.sh KEYSTORE ALIAS apks/phone/X.apk [more.apk …]
#   -> writes apks/phone/X-arm64.apk, signed with KEYSTORE/ALIAS (use the SAME key as X.apk,
#      or updates over an existing install fail). Passwords: env KS_PASS / KEY_PASS (default "android").
#   Then run tools/update-manifest.sh.
set -eu
[ $# -ge 3 ] || { sed -n '2,15p' "$0"; exit 1; }
KS=$1 ALIAS=$2; shift 2
KS_PASS=${KS_PASS:-android}; KEY_PASS=${KEY_PASS:-$KS_PASS}

find_bt() {
  local d
  for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -n "$d" ] && [ -d "$d/build-tools" ] || continue
    ls -d "$d"/build-tools/*/ 2>/dev/null | sort -V | tail -1 && return
  done
}
BT=$(find_bt); BT=${BT%/}
[ -x "$BT/apksigner" ] && [ -x "$BT/zipalign" ] || { echo "Android build-tools (apksigner, zipalign) not found" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

for apk in "$@"; do
  case "$apk" in *-arm64.apk) echo "skip $apk (already a variant)"; continue ;; esac
  out=${apk%.apk}-arm64.apk
  cp "$apk" "$tmp/in.apk"
  # drop native libraries and the old v1 signature files (zip -d exits 12 when nothing matched)
  zip -q -d "$tmp/in.apk" 'lib/*' 'META-INF/*.SF' 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/MANIFEST.MF' || [ $? = 12 ]
  "$BT/zipalign" -f -p 4 "$tmp/in.apk" "$tmp/aligned.apk"
  "$BT/apksigner" sign --ks "$KS" --ks-key-alias "$ALIAS" --ks-pass "pass:$KS_PASS" --key-pass "pass:$KEY_PASS" \
    --out "$out" "$tmp/aligned.apk"
  rm -f "$out.idsig"
  echo "built $out"
done
