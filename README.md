# HealthSync

Personal iOS/iPadOS app that incrementally exports Apple Health data (workouts, activity, heart, sleep, and more) as CSV into a folder you choose in the Files app — iCloud Drive or Google Drive — so your agents and tools can read it on a schedule.

Inspired by [wkaisertexas/HealthLens](https://github.com/wkaisertexas/HealthLens), rebuilt for remembered destinations, incremental watermarks, and Shortcuts automation.

## Features

- **Incremental sync** — remembers a watermark; each run exports only new samples (with a short overlap + UUID dedupe)
- **CSV output** — dense, agent-friendly; tiny JSON manifests per sync for metadata only
- **Remembered folder** — security-scoped bookmark to iCloud Drive or Google Drive via Files
- **Shortcuts** — `Sync Health Data` App Intent for daily automations
- **iPhone + iPad** — useful on a desk iPad that stays plugged in

## Output layout

Inside your chosen folder:

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

1. Open the project:
   ```bash
   cd /path/to/healthlens
   xcodegen generate   # if the .xcodeproj is missing
   open HealthSync.xcodeproj
   ```
2. In Xcode → Signing & Capabilities: select your **Team**, keep HealthKit enabled.
3. Run on a physical **iPhone or iPad** (HealthKit is limited in Simulator).
4. Grant Health read access for the metrics you enable.
5. Tap **Choose folder…** and pick e.g. `iCloud Drive/HealthSync` or `Google Drive/HealthSync`.
6. Tap **Sync Now** (first run backfills ~30 days).

## Daily Shortcut automation

1. Open **Shortcuts** → **Automation** → **+** → **Time of Day** (e.g. 7:00 AM).
2. Add action **Sync Health Data** (from HealthSync).
3. Optionally add **Show Notification** / **Log** with the returned summary text.
4. Turn off “Ask Before Running” if you want it unattended (iPadOS/iOS may still prompt depending on settings).

Siri phrases also work once the app is installed, e.g. “Sync health data with HealthSync”.

## Regenerating the Xcode project

This repo uses [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen   # once
xcodegen generate
open HealthSync.xcodeproj
```

## Notes

- True silent background export without Shortcuts is unreliable for HealthKit + Files; daily Shortcuts is the intended cadence.
- Read-only HealthKit: the app requests access then queries (it does not treat `authorizationStatus` as a hard gate).
- Reset the watermark in the app if you need another 30-day backfill.
