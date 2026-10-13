#!/bin/bash
# Run on your Mac. Signing uses the account and certificates in Xcode/Keychain.
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
if [[ $# -lt 1 || $# -gt 2 || ! "$1" =~ ^[1-9][0-9]{0,8}$ ]]; then
  echo "Usage: bash scripts/testflight.sh BUILD_NUMBER [--upload]" >&2
  exit 2
fi
if [[ $# -eq 2 && "$2" != "--upload" ]]; then
  echo "The only supported option is --upload (internal TestFlight only)." >&2
  exit 2
fi
[[ "$(uname -s)" == Darwin ]] || { echo "Requires macOS and Xcode." >&2; exit 1; }
major="$(xcodebuild -version | awk '/^Xcode / {split($2,v,"."); print v[1]}')"
[[ "$major" -ge 26 ]] || { echo "Select Xcode 26 or newer with xcode-select." >&2; exit 1; }
[[ -f Config/Google.local.xcconfig ]] || { echo "Configure gitignored Config/Google.local.xcconfig first." >&2; exit 1; }
archive="$PWD/build/TestFlight/HealthSync-$1.xcarchive"
[[ ! -e "$archive" ]] || { echo "Archive already exists; choose a fresh build number." >&2; exit 1; }
mkdir -p "$(dirname "$archive")"
xcodebuild -project HealthSync.xcodeproj -scheme HealthSync \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$1" archive
app="$archive/Products/Applications/HealthSync.app"
client_id="$(/usr/libexec/PlistBuddy -c 'Print :GIDClientID' "$app/Info.plist")"
scheme="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$app/Info.plist")"
[[ "$client_id" == *.apps.googleusercontent.com && "$scheme" == com.googleusercontent.apps.* ]] || {
  echo "Archive has missing/invalid Google OAuth configuration; refusing upload." >&2; exit 1;
}
[[ -f "$app/PrivacyInfo.xcprivacy" ]] || { echo "Archive is missing its privacy manifest." >&2; exit 1; }
if [[ "${2:-}" == "--upload" ]]; then
  xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist Config/TestFlightExportOptions.plist \
    -exportPath "$PWD/build/TestFlight/upload-$1" -allowProvisioningUpdates
  echo "Upload command completed. Verify processing and the Internal label in App Store Connect."
else
  echo "Archive ready: $archive"
  echo "Open it in Xcode Organizer and choose Distribute App > TestFlight Internal Only."
fi
