# Third-party notices

The APKs in `apks/` bundle or use the following components. Each stays under its own licence.

## Inside the watch apps

| Component | Used by | Licence | Source |
|---|---|---|---|
| **osmdroid** 6.1.20 | Maps | Apache-2.0 | https://github.com/osmdroid/osmdroid |
| **OkHttp** 3.12.13 and **Okio** 1.17.2 | Xiaozhi | Apache-2.0 | https://github.com/square/okhttp · https://github.com/square/okio |
| **Concentus** 1.0.2 (pure-Java Opus codec) | Xiaozhi | BSD-style (same terms as Opus) — see upstream | https://github.com/lostromb/concentus |
| **Cactus engine** (`libcactus`) and **Whistle** speech model (16.9 MB) | Maps (offline voice search) | Apache-2.0 (engine and model card) | https://github.com/cactus-compute/cactus · https://huggingface.co/Cactus-Compute/whistle |
| **Ticwear / Mobvoi SDK client library** (`mobvoi-api.jar`) | Maps (watch GPS, via the Ticwear location service) | Mobvoi's terms — see upstream | https://github.com/ticwear/sdk |
| **Material icons** (vector drawables) | Maps | Apache-2.0 | https://github.com/google/material-design-icons |

A copy of the Apache-2.0 licence is at https://www.apache.org/licenses/LICENSE-2.0.

## Data and services the apps talk to (nothing is bundled)

* **OpenStreetMap** map data © OpenStreetMap contributors, ODbL — https://www.openstreetmap.org/copyright.
  Tiles come from the public OSM tile servers (https://operations.osmfoundation.org/policies/tiles/);
  place search falls back to **Nominatim** (usage policy: max. 1 request/second).
* **BRouter** public instance (https://brouter.de) for keyless routing — please keep use light.
* **Google Maps Platform** (Map Tiles, Places, Routes) only with *your own* API key and under Google's terms;
  attribution is shown in the app.
* **Xiaozhi** voice service — under that project's terms.

## Modified Mobvoi software (phone apps)

`apks/phone/ticwear-companion-a16.apk` (Ticwear Global companion 4.9.1) and `apks/phone/mobvoi-store-a16.apk`
(Mobvoi Store 1.3.1) are **modified builds of proprietary software owned by Mobvoi Inc.** The changes are limited to
compatibility with current Android (target SDK, runtime-permission request, `FileProvider`-based install hand-off,
routing installs to *Install on Watch*). They are distributed here without any licence from Mobvoi, for
interoperability with watches that can no longer be served otherwise, and are not covered by this repository's MIT
licence. Mobvoi's rights remain with Mobvoi; if you are the rights holder and want them removed, open an issue.

## Not included

The Ticwear firmware itself and the watch-side install bridge (it needs the system partition) are not part of this
repository.
