# Sonora with Home Assistant

Sonora can talk to **Home Assistant's Assist** instead of (or as well as) the Xiaozhi service. Pick the
assistant in the app's settings: **Settings › Assistant › Xiaozhi | Home Assistant**.

It uses Home Assistant's normal WebSocket API with a long-lived access token. The watch connects *out* to
Home Assistant, so it works on Wi-Fi, through the phone's internet (Ticwear companion) when Wi-Fi is off,
and with a remote address such as Nabu Casa. It does **not** make the watch a Home Assistant "voice satellite"
device (no announcements or timers pushed from Home Assistant).

## 1. Create a token (Home Assistant)
Your profile (bottom-left) › **Security** › *Long-lived access tokens* › **Create token**. Copy it — Home Assistant
shows it only once. Treat it like a password: it gives full access to your Home Assistant.

## 2. Give the watch the address and token
The token is far too long to type on the watch, so set it once from a computer with `adb`
(the watch must be connected and awake):

```bash
adb shell am start -n org.xzwatch/.SettingsActivity \
  --es backend ha \
  --es ha_url http://homeassistant.local:8123 \
  --es ha_token YOUR_LONG_LIVED_TOKEN
```

* `ha_url`: your Home Assistant address, e.g. `http://192.168.1.20:8123` or `https://xxxx.ui.nabu.casa`.
  `host:port` without a scheme is accepted too. You can also edit it on the watch (Settings › Home Assistant URL).
* The token is stored only in the app's private storage and is never shown again; the settings screen just says *Saved ✓*.
* Remove the token: `adb shell am start -n org.xzwatch/.SettingsActivity --ez clear_ha_token true`
  (an empty `--es` value gets lost by `adb shell`, hence the separate flag).
* `SecurityException: Permission Denial … not exported`: the watch has an older Sonora build. Run `install-watch`
  again to update it. Only `adb` (and Sonora itself) can open this screen with settings; other watch apps cannot.

## 3. Check and choose a pipeline
In the app: **Settings › Home Assistant › Test connection** shows your Home Assistant version and how many
Assist pipelines it found. Tap **Pipeline** to cycle through them (default = Home Assistant's preferred pipeline).
The pipeline decides the language, speech-to-text, conversation agent and voice. `adb` equivalent:
`--es ha_pipeline PIPELINE_ID`.

## Using it
* Tap the orb (or hold it in *Hold* mode) and speak. The orb shows the usual states; the answer is shown as text
  and spoken with the pipeline's voice.
* The microphone stays closed after an answer, **unless Home Assistant asks a follow-up question** — then the
  watch listens again and keeps the conversation going.
* Home Assistant decides when you stopped speaking; the watch has a backup silence detector (about 1.8 s of silence,
  8 s with no speech, 15 s maximum).
* Short messages on the status chip: *Didn't catch that* (nothing recognised), *Home Assistant rejected the token*,
  *Open settings: set Home Assistant URL and token*.

## Notes
* Speech-to-text speed depends on your Home Assistant setup; a few seconds between the end of your speech and the
  reply is normal for a local Whisper-style engine.
* The pipeline must have text-to-speech configured, otherwise there is no spoken answer.
* Make sure the watch can reach the address you entered (same Wi-Fi, or a public/remote URL when using the phone's internet).
