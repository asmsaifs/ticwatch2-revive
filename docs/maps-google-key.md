# Google Maps key for the watch Maps app

The app works without a key (OpenStreetMap). With your own Google Maps Platform key it adds the
**Map** and **Satellite** (with road labels) layers. You create and install the key yourself.

## 1. Create the key (Google Cloud console, on your phone or computer)
1. https://console.cloud.google.com/ → create a project (e.g. "watch-maps").
2. Billing → link a billing account (required by Google Maps Platform; there is a monthly free usage tier —
   check current pricing). Set a **budget alert** and, under the API's *Quotas*, a low daily cap.
3. APIs & Services → Library → enable **Map Tiles API**.
   Also enable **Places API (New)** (search and nearby places) and **Routes API** (directions) if you want them from Google.
4. APIs & Services → Credentials → *Create credentials → API key*.

## 2. Restrict the key (recommended)
- **API restrictions:** "Restrict key" → select only *Map Tiles API* (add Places API (New) / Routes API later).
- **Application restriction (optional, test it):** *Android apps* → package `org.xzwatch.maps`,
  SHA-1 `A7:FB:30:CD:EB:8C:AB:A6:90:5E:13:A0:C9:0A:B0:E2:13:FC:35:9F`.
  The app sends the matching `X-Android-Package` / `X-Android-Cert` headers on the session call **and on
  every tile download** — verified working with Map Tiles API on 2026-11-07 (tiles returned 403 until the
  headers were added to tile requests too).

## 3. Put it on the watch (Debug over Wi-Fi on)
```bash
adb -s WATCH_IP:PORT shell am start -n org.xzwatch.maps/.MapActivity --es google_key YOUR_KEY
```
The map switches to Google. Tap the top-left button to cycle **Map → Sat → OSM**.

Optional: `--es layer map|satellite|osm` picks the layer directly.

Remove the key:
```bash
adb -s WATCH_IP:PORT shell am start -n org.xzwatch.maps/.MapActivity --ez clear_google_key true
```

## Notes
- The key lives only in the app's private storage on the watch.
- Errors (bad key, API not enabled, quota) show as a toast and the map falls back to OSM.
- Google's terms: attribution ("Google Maps · Map data ©…") stays visible; tiles are cached only per
  Google's cache headers; no offline download/prefetch.
