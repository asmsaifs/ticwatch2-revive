# ticwatch2-revive

**Bring the Mobvoi Ticwatch 2 back to life.**

The Ticwatch 2 (2016, Android 5.1 / *Ticwear 2*, MediaTek MT2601, 400×400 round screen, 512 MB RAM) is a nice
little watch with GPS, heart-rate sensor, speaker and microphone, but it was abandoned years ago:

* the stock voice assistant and app store depend on cloud services that are gone or unreliable,
* Android 5.1 is too old for Google Play services, most apps from the last decade, and — since
  its trust store stops at 2015 — for a growing number of HTTPS sites,
* the original phone companion app is so old that current Android versions refuse to install it,
* the firmware logs so aggressively that it fills the watch's storage.

This repository collects what is needed to make the watch useful again:

| Part | What it is |
|---|---|
| **Sonora** (watch app) | A voice assistant for the watch — talk to it, it talks back. Works with the open *Xiaozhi* AI service or with your own **Home Assistant** (Assist) |
| **Maps** (watch app) | OpenStreetMap / Google maps with search, nearby places, saved places, routing and turn-by-turn navigation, built for a round 400×400 screen |
| **Ticwear companion** (phone app, patched) | Mobvoi's phone companion rebuilt so it installs and runs on **Android 14–16** — pairs the phone with the watch, syncs apps and gives the watch internet over Bluetooth |
| **Mobvoi Store** (phone app, patched) | The old Ticwear app store, patched so installing from it works on current Android |
| **Install on Watch** (phone app + small watch receiver) | Installs old, low-target-SDK `.apk` files on a modern Android phone and sends watch apps to the watch over Bluetooth |
| **Ticwear home patch** (watch) | Makes the watch's own voice launches — swipe right on the watch face, "OK Tico", the wrist gesture — open Sonora instead of Mobvoi's dead Tico assistant |
| **`install-watch`** | One script (macOS · Linux · Windows) that installs/updates the watch apps and the Install on Watch receiver, applies the home patch and switches off the log-filling system apps |
| **`install-phone`** | Same idea for the phone app |
| **Flashing guide** | How to put the old, known-good ROM back on the watch |

> **Not affiliated with** Mobvoi, Xiaozhi, Home Assistant / Nabu Casa, Google, OpenStreetMap or Cactus Compute. Everything here is a
> hobby project, provided as is. See [Disclaimer](#disclaimer).

---

## Contents

1. [Quick start](#quick-start)
2. [What you need](#what-you-need)
3. [Connect the watch](#connect-the-watch)
4. [The watch installer](#the-watch-installer)
5. [The phone installer](#the-phone-installer)
6. [The apps](#the-apps)
7. [Flash the old ROM](#flash-the-old-rom)
8. [How updates work](#how-updates-work-and-how-to-publish-one)
9. [Troubleshooting](#troubleshooting)
10. [Repository layout](#repository-layout)
11. [Credits, licences, disclaimer](#credits-licences-disclaimer)

---

## Quick start

```bash
git clone https://github.com/asmsaifs/ticwatch2-revive.git
cd ticwatch2-revive
```

Connect the watch (see [Connect the watch](#connect-the-watch)), then run **one** of:

| OS | Watch apps | Phone app |
|---|---|---|
| macOS / Linux | `./install-watch.sh` | `./install-phone.sh` |
| Windows | double-click `install-watch.bat` | double-click `install-phone.bat` |

That's all. Run it again whenever you like (after a factory reset, or when new versions were published here):
apps that are already up to date are skipped.

No `git`? Use **Code → Download ZIP** on GitHub, unzip, and run the same scripts — they fetch newer files from
the repository on their own.

---

## What you need

* A Ticwatch 2 (codename *mercury*). Written for the international ROM **Tic_4.13.0_intl_a1** (beta)
  (Android 5.1, `userdebug` build); other Ticwear 2 builds probably work but are untested.
* A computer with **macOS, Linux or Windows 10/11**. The scripts need nothing but a terminal / PowerShell; if
  Android's `adb` tool is missing they offer to download Google's official *platform-tools* for you.
* For the phone installer: an Android phone with **USB debugging** (or *Wireless debugging*) enabled.
* Optional, per feature: a Google Maps API key (better maps/search/routing), an account on the Xiaozhi service, or a Home Assistant server with a long-lived access token.

---

## Connect the watch

The watch has no USB data port (only charging contacts), so adb works **over Wi-Fi**.

1. On the watch: **Settings → About →** tap **Build number** seven times to unlock *Developer options*.
2. **Settings → Developer options →** switch on **ADB debugging** and **Debug over Wi-Fi** (wording may vary).
   The screen shows an address like `192.168.1.50:5555`.
3. Put the watch **on its charger** and keep the screen awake — a sleeping watch drops the Wi-Fi link.
4. Run the installer. It looks for the watch itself; if it cannot find it, it asks for that address
   (or pass it: `./install-watch.sh --addr 192.168.1.50:5555`).

If you flashed the `userdebug` ROM described [below](#flash-the-old-rom), adb needs no authorisation prompt and
`adb root` works.

---

## The watch installer

```text
./install-watch.sh [options]            (Windows: install-watch.bat [options])

  --addr IP:PORT   connect to the watch over Wi-Fi first
  --no-disable     only install/update apps, leave system apps alone
  --no-home-patch  do not patch Ticwear home (voice launches keep opening Tico)
  --restore        undo: re-enable the system apps this script disabled, put the original Ticwear home back
                   and remove the Install on Watch receiver (restarts the watch)
  --force          replace an app that was installed with a different signing key (erases its data)
  --offline        do not look for newer files online
  --yes            answer "yes" to prompts (e.g. downloading platform-tools)
  --dry-run        show what would happen, change nothing
```

What it does, in order:

1. **Looks for newer versions** — `git pull` if this folder is a clone, otherwise it downloads the changed files from
   this repository (see [How updates work](#how-updates-work-and-how-to-publish-one)).
2. **Finds `adb`** (offers to download platform-tools if it is missing).
3. **Finds the watch** among the connected devices (it recognises it by the product name `mercury`).
4. **Installs or updates each watch app** in [`manifest.tsv`](manifest.tsv). It compares the checksum of the APK
   *on the watch* with the one in the repository, so unchanged apps are skipped and any new build is installed.
   User data is kept (`adb install -r`).
5. **Installs the Install on Watch receiver** (`org.xzwatch.bridge.watch`), the watch half of
   [Install on Watch](#install-on-watch--phone-app). It needs system rights to install apps, so it is copied to
   `/system/priv-app/XzBridge/` (needs adb root, like the home patch) and the watch **restarts once** at the end of the
   run so Android picks it up. Only when it is missing or changed; a reflash removes it, re-running brings it back.
6. **Patches Ticwear home** so the watch's voice launches open Sonora — see
   [Ticwear home patch](#ticwear-home-patch--voice-launches-open-sonora). Skipped with `--no-home-patch`, on a ROM
   other than the one below, or without adb root.
7. **Disables unneeded system apps** listed in [`system-apps.tsv`](system-apps.tsv), using `pm disable`
   (reversible, nothing is deleted). Currently:

   | Package | Why |
   |---|---|
   | `com.mediatek.mtklogger` | MediaTek logger — on this ROM it fills `/sdcard/mtklog` with hundreds of MB until storage is full |
   | `com.mobvoi.ticwear.mtklog` | Mobvoi's "TicLog" front-end for the same logging |

   Disabled state lives in the watch's data partition, so **a factory reset brings these apps back — just run the
   installer again.** Edit `system-apps.tsv` to add or remove packages
   (`adb shell pm list packages` lists what is installed). Undo everything with `--restore`.

Examples:

```bash
./install-watch.sh --addr 192.168.1.50:5555      # first run over Wi-Fi
./install-watch.sh --dry-run                     # see what it would do
./install-watch.sh --no-disable                  # apps only
./install-watch.sh --restore                     # re-enable the system apps, original Ticwear home, no receiver
```

On Windows the same options work (`install-watch.bat --addr 192.168.1.50:5555`).
If PowerShell refuses to run scripts, the `.bat` launcher already passes `-ExecutionPolicy Bypass` for that one run.

After the **first** install, on the watch:

* Ticwear asks per app for permissions — allow **Microphone** for Sonora and Maps (and Internet if asked).
* Maps: optionally set a Google key ([Maps](#maps--navigation-for-the-round-screen)). Sonora: with Xiaozhi, open it once to get a pairing code; with Home Assistant, see [docs/home-assistant.md](docs/home-assistant.md).

---

## The phone installer

```text
./install-phone.sh [options]            (Windows: install-phone.bat [options])

  --serial ID            pick a device when several are attached (see: adb devices)
  --pair HOST:PORT CODE  pair over Wireless debugging first (Android 11+): the pairing address + 6-digit code
  --connect HOST:PORT    connect over Wireless debugging (the main address, not the pairing one)
  --force / --offline / --yes / --dry-run    as above
```

1. On the phone: **Settings → About phone →** tap *Build number* 7× → **Developer options →**
   enable **USB debugging** (or **Wireless debugging**).
2. Plug the phone in and accept the "Allow USB debugging?" prompt (or use `--pair` / `--connect`).
3. Run `./install-phone.sh`.

It installs/updates the three phone apps — **Ticwear companion**, **Mobvoi Store** and **Install on Watch** (the same
up-to-date check as above) — and grants *Install on Watch* the permissions it needs (notifications, Bluetooth,
all-files access) where Android allows that from adb. The companion and the store ask for their own permissions
the first time you open them — allow them, the companion needs calendar, contacts, SMS and phone access to sync
those to the watch.

**64-bit-only phones** (recent Snapdragon, Tensor and Dimensity chips, e.g. Pixel 7 and newer, many 2024+ phones)
cannot run 32-bit ARM code, and Mobvoi's apps only contain 32-bit native libraries. The installer detects this and
installs the `-arm64` builds instead: the same apps, same signing key, with the native libraries removed. Those
libraries only serve optional extras (phone-side voice wake-up, Baidu/Sogou maps, Weibo and UnionPay); pairing, app
sync, notifications and the watch's internet-over-Bluetooth are plain Java and work the same.

**Already have the original companion on the phone?** The patched apps are signed with a different key than
Mobvoi's, so Android refuses to update over the originals (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Re-run with
`--force` to uninstall the original first (this erases its data, i.e. the existing pairing).
**A watch that was paired with another companion has to be factory-reset before it pairs with this one** — that
is how Ticwear works, not something these builds change.

The phone and the watch are told apart automatically, so both can be plugged in at the same time.

---

## The apps

### Sonora — voice assistant for the watch

`org.xzwatch` · watch app (formerly "Xiaozhi"; same package, so it updates in place and keeps your settings).
Choose the assistant under **Settings › Assistant**:

* **Xiaozhi** — the open **Xiaozhi** AI voice service ([xiaozhi.me](https://xiaozhi.me)).
  First start shows a pairing code: enter it in your Xiaozhi account to activate the device. The service URL can be changed in settings.
* **Home Assistant** — your own server's **Assist** pipeline (any language/voice/agent you set up there).
  Needs the server address and a long-lived access token; setup, the follow-up-question behaviour and troubleshooting are in
  [docs/home-assistant.md](docs/home-assistant.md).

Common to both:

* Press the orb (or hold it — switchable in settings) and talk; replies are spoken back.
* *Tap* mode keeps the conversation going hands-free (with Home Assistant the microphone reopens only when it asks a follow-up
  question); *Hold* mode is push-to-talk.
* Built for the round screen: a state-coloured animated orb (idle / listening / thinking / speaking) and a transcript
  that **scrolls and shrinks** so long sentences stay readable (non-Latin text such as Bangla works).
* Works over the watch's Wi-Fi, or — when Wi-Fi is off — through the phone's internet via the Ticwear companion.
* Xiaozhi audio is Opus-encoded on the watch (pure-Java encoder, no native code) over a WebSocket; Home Assistant gets plain
  16 kHz PCM over its WebSocket API and the spoken answer is played from the file it returns.
* Swipe right on the watch face or say **"OK Tico"** to open it — that is the [home patch](#ticwear-home-patch--voice-launches-open-sonora).

### Ticwear home patch — voice launches open Sonora

`com.mobvoi.ticwear.home` · system app on the watch · **a modified build of part of Mobvoi's watch launcher**

Ticwear sends every voice launch — swipe right on the watch face, the "OK Tico" hotword, the raise-and-talk wrist
gesture — to its built-in *Tico* assistant, whose servers are gone. The patch changes that one hand-off
(`VoiceContainer.a(String)`) to start Sonora (with `autostart`, so it listens right away) and then closes the Tico
panel. If Sonora is not installed, Tico opens as before.

How it is applied: Ticwear home is signed with the platform key, so its APK cannot be rebuilt. Instead
`install-watch` replaces only its compiled code: it copies the patched `classes.dex`
([`patches/ticwear-home/`](patches/ticwear-home)) to the watch, compiles it there with the watch's own `dex2oat`
against the watch's own boot image (about a minute), and swaps the result in for
`/system/priv-app/MobvoiWearHome/arm/MobvoiWearHome.odex`. The APK is untouched.

* **Needs adb root** and is made for **Tic_4.13.0_intl_a1** only: the installer checks the checksum of the original
  odex and skips the step on any other Ticwear home.
* The original odex is kept on the watch in `/system/xzpatch/` — it survives a factory reset, as does the patch
  itself (both live in `/system`). `install-watch --restore` puts the original back; reflashing the ROM does too.
* Re-running the installer is cheap: it recognises an already-patched watch and only recompiles when the patch in
  the repository changes.

### Maps — navigation for the round screen

`org.xzwatch.maps` · watch app

* **Maps:** OpenStreetMap out of the box; with your own Google key also Google *Map* and *Satellite* layers.
* **Search:** by keyboard, or by **voice** with a built-in, fully **offline** speech recogniser
  (Cactus *Whistle*, 17 MB, English/German/French/Spanish/Italian/Dutch/Polish — place names are best said in English).
  Search uses Google Places when a key is set, OpenStreetMap Nominatim otherwise.
* **Nearby:** one-tap category chips on the search screen — Food, Cafe, ATM, Fuel, Pharmacy, Hospital, Mosque,
  Grocery, Hotel — list places around you, nearest first (Google Places nearby search with a key, Nominatim without).
* **Saved places:** star a place from its screen or long-press a search result. A dropped pin asks what to call it —
  *Home*, *Work* or a name you type — and Home/Work get their own house/briefcase icons. The *Saved* chip opens your list
  (nearest first; tap to show on the map, long-press to remove, with undo), and saved places appear on the map as
  small amber stars.
* **Uncluttered map:** the on-map buttons fade out after a few seconds; tap the map to bring them back.
* **Swipe to pan:** the map screen turns off Ticwear's swipe-to-exit so right-to-left drags pan the map. To leave,
  swipe right from the very left edge of the screen; the other screens still swipe-to-exit as usual.
* **Routing:** walk, bike and drive. Google Routes API when a key is set, otherwise the free
  [BRouter](https://brouter.de) service (OpenStreetMap data, no key).
* **Turn-by-turn navigation:** big turn arrow and distance, vibration patterns for "prepare" and "turn now",
  automatic re-routing, screen wake on each alert.
* Recent places, long-press the map to drop a pin.
* Location comes from the watch's own GPS through the Ticwear location service.

**Google key (optional).** Create an API key in Google Cloud (Google requires a billing account; there is a monthly free
tier — set a budget alert), enable *Map Tiles API*, *Places API (New)* and *Routes API*, and send the key to the
watch with adb — there is no text field for it on the watch:

```bash
adb shell am start -n org.xzwatch.maps/.MapActivity --es google_key YOUR_KEY
```

The key stays in the app's private storage on your watch; it is not part of this repository.
Without a key everything still works with OpenStreetMap-based services. Step-by-step, including how to restrict the
key to this app: [docs/maps-google-key.md](docs/maps-google-key.md).

---

### Install on Watch — phone app

`org.xzwatch.bridge.phone` · Android phone app

Android 14+ refuses to install apps built for old Android versions (target SDK < 24) — which is exactly what the
Ticwear/Wear ecosystem consists of. This app registers as a handler for `.apk` files ("Open with → Install on
Watch"), and:

* installs such an old app **on the phone** by using the phone's own adb connection with the
  *bypass-low-target-sdk-block* flag (one-time setup: Wireless/USB debugging on, `adb tcpip 5555` once after each
  phone reboot, and accept the "Allow USB debugging?" prompt once);
* detects apps that embed a watch app (Wear/Ticwear "micro apps") so the watch version syncs through the companion;
* when the phone's adb is not reachable (no `adb tcpip 5555` since the last reboot), skips the phone part of such
  an app and sends its embedded watch app straight to the watch over Bluetooth instead;
* sends pure watch apps (no phone part) straight to the watch.

Normally the Ticwear companion copies a store app's watch part to the watch by itself — but only after the phone
part is installed, which Android 14+ blocks for these old apps without adb. Sending over Bluetooth needs the small
**receiver on the watch** (`org.xzwatch.bridge.watch`, "Install Bridge"): `install-watch` puts it in
`/system/priv-app` (it needs system rights to install apps). It accepts APKs only from the first phone that sends
one (trust on first use).

### Ticwear companion — patched for current Android

`com.mobvoi.companion.global` 4.9.1 · phone app · **a modified build of Mobvoi's own companion app**

The original declares an old target SDK (21), which Android 14+ refuses to install. This build changes only
what is needed for modern Android: target SDK raised to 24 (so it installs normally, no adb flag), and a runtime
permission request at start-up (the app predates runtime permissions and crashed without them). Everything else —
pairing, notification sync, app sync, the internet-over-Bluetooth proxy for the watch — is Mobvoi's original code.
Verified on an Android 16 phone: pairing works, the watch syncs data and apps over the Data Layer.
`ticwear-companion-a16-arm64.apk` is the same build without its 32-bit native libraries, for 64-bit-only phones
(see [the phone installer](#the-phone-installer)).

### Mobvoi Store — patched

`com.mobvoi.appstore` 1.3.1 · phone app · modified build of Mobvoi's app store

Same treatment (target SDK 24, runtime permissions) plus a fix for installing: Android no longer accepts the
`file://` links the store used to hand the installer, so installs now go through a `FileProvider`. If *Install on
Watch* is present, the store sends downloaded apps straight to it, which is what lets old (target SDK < 24) store
apps be installed on the phone — after which the companion syncs the embedded watch app to the watch automatically.
`mobvoi-store-a16-arm64.apk` is the same build without its 32-bit native libraries, for 64-bit-only phones.

> **About these two builds.** They are derived from software owned by Mobvoi Inc., which is not open source.
> They are included here only because the originals no longer install on current Android and the service is no
> longer maintained; they are not endorsed by Mobvoi, and Mobvoi may ask for them to be removed. See
> [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

## Flash the old ROM

Only do this if you want to (re)install the stock firmware. **It erases everything on the watch.**

**ROM to use:** `Tic_4.13.0_intl_a1` beta (`mercury_i18n`, Android 5.1 LMY47I, `userdebug`). Its advantages here: international
build, `adb root` works, no adb authorisation prompt.

* **Download:** https://drive.google.com/file/d/1wUHszY569mBPEb_MoSA3fjyQycJK-Ewf/view?usp=sharing
* **SHA-256:** `500512999d8167b6eade1375f1e454a6d6f5e5fa4e3e855d81f7225d43e40130`
  (file: `Ticwatch2-i18n-beta-Tic_4.13.0_intl_a1-1505989793818.zip`, 278,768,935 bytes — check with `shasum -a 256 <file>` on macOS/Linux or `Get-FileHash <file>` in Windows PowerShell)

Steps:

1. Charge the watch (≥ 50 %) and keep it on the charger. Back up anything you want to keep — `/data` is wiped.
2. Download the ROM `.zip`. **Do not unzip it.**
3. Connect adb over Wi-Fi ([Connect the watch](#connect-the-watch)) and copy the zip to the watch
   (≈ 300 MB — it takes about 15 minutes over Wi-Fi adb, so keep the screen awake and **do not run two copies at once**):

   ```bash
   adb push Ticwatch2-i18n-beta-Tic_4.13.0_intl_a1-1505989793818.zip /sdcard/update.zip
   adb shell md5 /sdcard/update.zip      # compare with: md5sum Ticwatch2-i18n-beta-Tic_4.13.0_intl_a1-1505989793818.zip  (macOS: md5 -q)
   ```
4. Start the installation — **pick one** of the two ways:

   **Option A — on the watch (no root needed).** With the zip in `/sdcard/update.zip` from step 3:

   1. On the watch open **Settings → Developer info** and tap **Install manually**.
   2. Wait while the watch processes the package and installs it. It may restart and the screen can go black for a
      while — that is normal. **Do not touch the watch or take it off the charger** until it is back.

   If nothing happens, check that the *System Update* app is not disabled
   (`adb shell pm enable com.mobvoi.ticwear.systemupdate` turns it back on).

   **Option B — with adb (needs `adb root`, i.e. a `userdebug` ROM is already running).** Tell recovery to install the
   package and reboot into it:

   ```bash
   adb root
   adb shell "mkdir -p /cache/recovery; echo --update_package=/sdcard/update.zip > /cache/recovery/command"
   adb reboot recovery
   ```

   Either way, recovery then installs the package (a few minutes, progress/black screen), formats `/data`, and the
   watch reboots. The first boot is slow.
5. Re-enable ADB debugging, then run [`install-watch`](#the-watch-installer) to put the apps and the home patch back
   (flashing replaces `/system`, so the patch has to be applied again).

Good to know:

* The stock recovery only accepts packages **signed by Mobvoi**. Re-packed or re-signed ROMs are rejected —
  and replacing the recovery to get around that is risky. Use the original zip.
* Option B needs `adb root`; on firmware without it (for example the Chinese 4.15 builds) use Option A. The file you
  copy to `/sdcard/update.zip` is the same either way.
* After flashing, `/data` is empty: pair the phone again, grant the per-app permissions again, and re-run the installer
  (which also re-applies the system-app changes and the home patch).

---

## How updates work (and how to publish one)

The installers do **not** compare version numbers; they compare **checksums**. For every app in
[`manifest.tsv`](manifest.tsv) they read the APK that is installed on the device, take its MD5, and compare it with the
repository's. Different → install the repository's version. Same → skip.

For users that means: *run the installer again* — it first runs `git pull` (clones) or downloads the changed files
(ZIP downloads), then installs whatever differs. No version bookkeeping to forget.

**To publish a new version** (maintainer):

1. Replace the file in `apks/watch/` or `apks/phone/` with the new build — **sign it with the same key as before**;
   Android refuses to update an app signed with a different key (users would need `--force`, which erases app data).
2. Run `tools/update-manifest.sh` (refreshes the checksums in `manifest.tsv`). The GitHub Action in
   `.github/workflows/manifest.yml` does the same automatically on every push that touches `apks/`.
3. `git commit` and `git push`.

**To add a new app:** put the APK under `apks/<target>/`, add a row to `manifest.tsv`
(`target<TAB>package<TAB>file<TAB>md5<TAB>name`, target = `watch` or `phone`), then run `tools/update-manifest.sh`.
A watch app that needs system rights goes under `apks/watch-system/X.apk` (target `watch-system`); the watch
installer copies it to `/system/priv-app/X/X.apk` and restarts the watch.

**64-bit-only phones:** when a phone APK contains only 32-bit native libraries (`lib/armeabi-v7a/`), also build its
variant with `tools/make-arm64-variant.sh KEYSTORE ALIAS apks/phone/X.apk` (same key as `X.apk`). It writes
`X-arm64.apk`; `tools/update-manifest.sh` then marks the pair as target `phone64` / `phone32`, and the installer picks
the one that matches the phone. Rebuild the variant whenever `X.apk` changes.

Using a fork? The scripts read the repository address from `git remote origin`; for a ZIP download set
`TICWATCH2_REVIVE_RAW=https://raw.githubusercontent.com/<you>/ticwatch2-revive/main` or edit `DEFAULT_RAW` in
`lib/common.sh` / `lib/common.ps1`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `adb` says the watch is **offline**, or the link drops mid-install | The watch's Wi-Fi sleeps with the screen. Put it on the charger (the installer then also keeps the screen on), toggle *ADB debugging* off/on, re-run. |
| "no Ticwatch 2 found" | Check the IP:PORT in Developer options, that the computer is on the same network, and run `adb connect IP:PORT`. |
| Apps on the watch **time out on every connection** although Wi-Fi is connected | The ROM can leave its Doze firewall chain attached while the watch is awake, which drops all third-party app traffic. With root adb: `adb root; adb shell ndc firewall detach_specified_chain fw_doze` (a reboot also clears it). |
| Microphone does nothing / "Mic blocked" | Ticwear has its own permission gate: Settings → Apps → the app → allow Microphone. |
| Phone: `INSTALL_FAILED_NO_MATCHING_ABIS` | A 64-bit-only phone with an old copy of the installer. Update the folder (`git pull`, or download the ZIP again) and re-run — it then installs the `-arm64` builds. |
| Swiping right / "OK Tico" still opens Tico | Run `install-watch` again (after a reflash the patch is gone). If it says *skipped: needs adb root*, the watch is not on the userdebug ROM; *not the Tic_4.13.0_intl_a1 one* means a different Ticwear version — see [the home patch](#ticwear-home-patch--voice-launches-open-sonora). The first swipe right after the patch is applied is sometimes ignored; swipe again. |
| Install on Watch: *Watch did not answer* / cannot connect to the watch | The receiver is missing on the watch (a reflash removes it): run `install-watch`. If it says *skipped: needs adb root*, the watch is not on the userdebug ROM. Bluetooth must be on and the watch paired with the phone. |
| Install on Watch: *This old app needs the phone's adb* | Run `adb tcpip 5555` once (again after every phone reboot) with the phone on USB, then tap *Try again*. Apps with a built-in watch part go straight to the watch instead when adb is not set up. |
| Home Assistant setup: `SecurityException … not exported` | The watch has an older Sonora; run `install-watch` to update it, then repeat the `adb shell am start …` command. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | The app on the watch was signed with another key. `--force` replaces it (erases that app's data). |
| An HTTPS site fails with handshake / certificate errors | Android 5.1's trust store lacks newer roots (ISRG/Let's Encrypt, Google Trust Services, Amazon) and it cannot speak TLS 1.3-only servers. Choose services that still serve TLS 1.2 chained to older roots. |
| The watch will not pair with the new companion | A watch that was paired before must be factory-reset from the watch's Settings so it shows its pairing QR code again. |
| Storage keeps filling up | The MediaTek loggers are back (e.g. after a reset): re-run `install-watch`. Delete `/sdcard/mtklog` once. |
| Windows: "running scripts is disabled" | Use the `.bat` launchers — they bypass the policy for that single run. |

---

## Repository layout

```text
ticwatch2-revive/
├── README.md
├── install-watch.sh / .ps1 / .bat      watch installer (macOS+Linux / Windows)
├── install-phone.sh / .ps1 / .bat      phone installer
├── manifest.tsv                        which APKs exist, for which device, and their checksums
├── system-apps.tsv                     system apps the watch installer disables
├── apks/
│   ├── watch/   sonora-watch.apk  watch-maps.apk
│   ├── watch-system/  XzBridge.apk   (Install on Watch receiver, goes to /system/priv-app)
│   └── phone/   ticwear-companion-a16.apk  mobvoi-store-a16.apk  phone-bridge.apk
│                (+ *-arm64.apk: the same two Mobvoi apps for 64-bit-only phones)
├── patches/
│   └── ticwear-home/  MobvoiWearHome-classes.dex   (home patch, compiled on the watch by install-watch)
├── docs/        maps-google-key.md  home-assistant.md
├── lib/         shared installer code (common.sh, common.ps1)
├── tools/       update-manifest.sh, make-arm64-variant.sh (maintainer helpers)
├── .github/workflows/manifest.yml      keeps manifest.tsv in sync with apks/ and patches/
├── THIRD_PARTY_NOTICES.md
└── LICENSE
```

The watch apps and *Install on Watch* are signed with this project's key; the patched companion and store are
signed with a second key (`CN=companion-a16`) because Mobvoi's original signing key is not available. Their
`-arm64` copies use that same key, so a phone can switch between the two without losing data.

---

## Credits, licences, disclaimer

* Scripts: see [LICENSE](LICENSE). Bundled third-party components and their licences: see
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
* Map data © OpenStreetMap contributors (ODbL). Please respect the usage policies of the public OpenStreetMap tile,
  Nominatim and BRouter services; the apps are meant for personal use of one watch.
* Speech recognition: *Whistle* by Cactus Compute (Apache-2.0).

### Test status

| Piece | Verified |
|---|---|
| `install-watch.sh` — install, update, online sync, disable, `--restore` | on a real Ticwatch 2 from macOS |
| Ticwear home patch via `install-watch.sh` — apply, re-run, `--restore`, re-apply | on a real Ticwatch 2 (Tic_4.13.0_intl_a1): swipe right opens Sonora |
| Install on Watch receiver via `install-watch.sh` — install, re-run, remove, restart + check | on a real Ticwatch 2 (2026-11-09) |
| `install-watch.sh` / `install-phone.sh` on Linux | against a simulated adb device (Ubuntu) |
| `install-watch.ps1` / `install-phone.ps1` on Windows | with PowerShell 7 against a simulated adb device — not yet on a real Windows PC (home patch and receiver: logic tested against a simulated watch only) |
| `install-phone.sh` on a real phone | macOS → 64-bit-only Android 16 phone (Snapdragon SM7550): arm64 builds install and start |
| Flashing section | written from the stock recovery's behaviour; follow it carefully and report problems |

Reports and fixes are welcome.

### Disclaimer

This software is provided **as is**, without warranty. Installing apps, disabling system packages or flashing firmware
can make a device misbehave or, in the worst case, stop working. You do all of this at your own risk and should
back up first. This project is independent of, and not endorsed by, Mobvoi, the Xiaozhi project, Home Assistant / Nabu Casa, Google,
OpenStreetMap or Cactus Compute; all trademarks belong to their owners.
