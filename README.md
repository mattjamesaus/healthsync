# HealthSync

Personal iOS/iPadOS app that incrementally exports Apple Health data (workouts, activity, heart, sleep, and more) as CSV into a HealthSync folder in the user’s own Google Drive, so agents and tools can read it on a schedule.

The app signs into Google and uploads with the Drive REST API. It does not use the Files app Google Drive provider.

## Features

- **Incremental sync** — remembers a watermark; each run exports only new samples (with a short overlap + UUID dedupe)
- **CSV output** — dense, agent-friendly; tiny JSON manifests per sync for metadata only
- **Google Drive** — Google Sign-In plus `drive.file`; creates `My Drive/HealthSync`
- **Shortcuts** — `Sync Health Data` App Intent for daily automations
- **iPhone + iPad** — useful on a desk iPad that stays plugged in

## Output layout

Inside `My Drive/HealthSync`:

```text
samples/YYYY-MM.csv
workouts/YYYY-MM.csv
manifests/sync_<ISO8601>.json
```

Sample columns:

```text
datetime,end_datetime,type,unit,value,source,uuid
```

Dates are ISO-8601 UTC.

## Setup (local device)

1. Create a Google Cloud project, enable **Google Drive API**, and finish the OAuth consent screen with only `https://www.googleapis.com/auth/drive.file`.
2. Create an **iOS** OAuth client with bundle ID `com.mattjamesaus.HealthSyncApp` and Team ID `QRJV5T3359`.
3. Copy the client ID and reversed client ID into gitignored `Config/Google.local.xcconfig` (see `Config/Google.local.xcconfig.example`).
4. Open the project:
   ```bash
   cd /path/to/HealthSync
   xcodegen generate   # if the .xcodeproj is missing
   open HealthSync.xcodeproj
   ```
5. In Xcode → Signing & Capabilities: select your **Team**, keep HealthKit enabled.
6. Run on a physical **iPhone or iPad** (HealthKit is limited in Simulator).
7. Grant Health read access for the metrics you enable.
8. Tap **Connect Google Drive**, then **Sync Now** (first run backfills ~30 days).

Publish the OAuth consent screen to production before relying on daily Shortcuts. In Testing, refresh tokens for this scope expire after seven days.

## Daily Shortcut automation

1. Open **Shortcuts** → **Automation** → **+** → **Time of Day** (e.g. 7:00 AM).
2. Add action **Sync Health Data** (from Health Sync).
3. Optionally add **Show Notification** / **Log** with the returned summary text.
4. Turn off “Ask Before Running” if you want it unattended (iPadOS/iOS may still prompt depending on settings).

Siri phrases also work once the app is installed, e.g. “Sync health data with Health Sync”.

Shortcuts still cannot sync while the device is locked. HealthKit will not return samples, and the Keychain item may be unavailable before first unlock after boot.

## App icon

The app uses two sync arrows forming a heart, with light, dark, and grayscale
tinted appearances in `HealthSync/Assets.xcassets/AppIcon.appiconset`. The light
icon is opaque; the dark icon has a transparent background for iOS to fill.

The editable vector mark and separate arrow layers are in `design/app-icon`.
The concept was generated with image generation and converted to SVG paths.
To regenerate the PNG assets, install Pillow and CairoSVG (with the native Cairo
library), then run `python3 scripts/render-app-icons.py`.

These are asset-catalog icons. The SVG layers are also prepared for a future
layered Liquid Glass icon in Icon Composer; a `.icon` file is not included yet.

## Regenerating the Xcode project

This repo uses [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen   # once
xcodegen generate
open HealthSync.xcodeproj
```

## Notes

- True silent background export without Shortcuts is unreliable for HealthKit; daily Shortcuts is the intended cadence.
- Read-only HealthKit: the app requests access then queries (it does not treat `authorizationStatus` as a hard gate).
- Reset the watermark in the app if you need another 30-day backfill. That does not delete Drive files.
- Disconnect revokes the Google grant and clears the local file-id cache. It does not delete the Drive folder.

## Privacy

See [docs/privacy.html](docs/privacy.html). Health data stays on device until you connect Google. The app then writes CSV into that user’s Drive. The developer’s servers do not receive it.

## Error reporting

Sync failures and crashes are sent to Sentry. The client DSN lives in `Config/Secrets.xcconfig`. The Upload Debug Symbols build phase sends dSYMs when `SENTRY_AUTH_TOKEN` is set in the build environment or in gitignored `Config/SentryAuth.local.xcconfig` (see the example next to it). Authorization headers, tokens, CSV bodies, and Health samples are not attached.

## Private TestFlight distribution

See [the private beta runbook](docs/testflight.md) for Apple setup, a repeatable
Release archive/upload script, and physical-device reliability checks. Use
**TestFlight Internal Only** and the owner-only internal group. CI builds Debug
and Release without credentials; it does not upload or distribute builds.
