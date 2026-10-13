# HealthSync: owner-only TestFlight

## Distribution boundary

Use **TestFlight Internal Only**, not external TestFlight or public App Store
distribution. Create one internal group named **Personal devices**, containing
only the account holder. Do not create public links or external groups. Disable
automatic distribution initially so each build is deliberately selected.
Internal-only builds cannot be submitted for external testing or App Store
release. Builds expire after 90 days; upload a new build before expiry.

Bundle ID: `com.mattjamesaus.HealthSyncApp`; team: `QRJV5T3359`.
The existing target supports iPhone and iPad, with iOS/iPadOS 17 minimum.
The build SDK must meet Apple's upload requirements (currently Xcode 26+).
The SDK minimum does not require raising the app's deployment target.

## One-time Apple configuration

1. Sign into Apple Developer and App Store Connect as the membership owner.
   Confirm the selected team's ID is QRJV5T3359. Resolve any pending agreements
   yourself; do not store your password or verification codes in the repository.
2. Under Certificates, Identifiers & Profiles, locate the explicit identifier
   com.mattjamesaus.HealthSyncApp, or register it if absent. Enable HealthKit.
   The app reads HealthKit and requests no write types. It has no observer-query
   background delivery, so do not enable background delivery, clinical health
   records, or unrelated capabilities.
3. In App Store Connect > My Apps, reuse an existing app record for this bundle
   ID. Otherwise create an iOS app named Health Sync (or an available name),
   primary language English, SKU healthsync-personal, selecting that identifier.
   Do not create a second bundle ID.
4. In TestFlight, create the Personal devices internal group and add only the
   account holder's eligible App Store Connect user. Use the Apple Account that
   will accept the invitation in TestFlight on both devices. If that account
   differs from the owner account, resolve the account arrangement before
   inviting anyone; do not widen access casually.
5. Provide beta description/contact details when requested. Suggested description:
   "Personal beta exporting selected Apple Health records as CSV to the owner's
   Google Drive. Known watchdog termination remains under investigation."
6. Answer the build's export-compliance questions truthfully. The app uses HTTPS,
   Google authentication and SDKs; confirm the applicable encryption exemption
   before setting ITSAppUsesNonExemptEncryption. This change deliberately does
   not hardcode a legal classification.

## Build and upload on the physical Mac

Install/select Xcode 26+ and add the owner Apple Account in Xcode Settings >
Accounts. Confirm the team has distribution signing access. Keep automatic
signing; Xcode manages the required signing assets in the local Keychain.
An Apple Development-signed archive can be re-signed for distribution during
export; do not hardcode a certificate name or provisioning profile UUID.

Pull this branch (or main after merge). The checked-in project includes the
shared HealthSync scheme; project.yml preserves it when regenerating with
XcodeGen. Keep Config/Google.local.xcconfig gitignored and configure both
GID_CLIENT_ID and GID_REVERSED_CLIENT_ID using the existing iOS OAuth client.
That client must match the bundle ID and team. Never add a web client secret,
refresh/access tokens, .p12, private .p8 key, or provisioning profile to git.
OAuth client IDs are embedded application identifiers, not client secrets.

Choose a build number greater than every previously uploaded build. The
marketing version remains 1.0.0. The script never changes tracked version files
and never asks Apple to silently renumber the build:

```bash
bash scripts/testflight.sh 2
```

This creates a Release archive without uploading. Open the printed .xcarchive
in Xcode, review signing/entitlements and the archive privacy report, then choose
Distribute App > **TestFlight Internal Only**. If using the command line after
Apple setup and device smoke tests:

```bash
bash scripts/testflight.sh 3 --upload
```

Use a fresh number for every invocation. The export plist fixes the team,
automatic signing, upload destination and testFlightInternalTestingOnly=true.
The CLI uses the signed-in Xcode account; no App Store Connect API key is needed.
The script checks the archive's Google configuration and bundled manifest before
upload. Upload completion does not imply Apple processing has succeeded.

In App Store Connect, wait for processing, resolve compliance/validation issues,
and verify the build is visibly marked **Internal** before adding it to Personal
devices. If it is not marked Internal, do not distribute it; inspect the export
log and use Organizer's explicit internal-only option for a fresh build.

## Privacy review before the first upload

The app already includes a read-purpose string, HealthKit entitlement and bundled
PrivacyInfo.xcprivacy. The unused Health update purpose string does not cause a
write request: requestAuthorization uses toShare: []. The manifest now declares
UserDefaults reason CA92.1 for app-local preferences and watermarks.

Review the archive's aggregated privacy report including GoogleSignIn, AppAuth
and Sentry manifests. A privacy manifest is not a substitute for App Store
Connect privacy answers or the HealthKit privacy policy. The current declarations
include health, email, name and user ID for app functionality. Verify actual
collection/retention and linking before completing the questionnaire; do not
select "data not collected" merely because this is a personal app.

Sentry is enabled whenever a DSN is configured and has tracing at 100%.
sendDefaultPii=false and header scrubbing do not prove all event data is free of
health information. Audit captured errors, breadcrumbs and transactions; inspect
the watchdog event without publishing patient data or OAuth credentials.
Diagnostics must be covered by the policy and privacy answers. Keep archives and
dSYMs locally; optionally configure the existing gitignored Sentry auth config
and sentry-cli for symbolication.

docs/privacy.html is an existing policy source; its deployment/reachability has
not been verified. Provide an accessible rendered policy URL in App Store Connect
and Google consent configuration. Review the revised Sentry wording and ensure
the policy remains accurate. Review adding an in-app policy link before wider
testing. Google consent in Testing can expire Drive refresh tokens after seven
days; verify its status separately from Apple distribution.

## Install and verify on iPhone and iPad

Install Apple's TestFlight app on each physical device, accept the internal
invitation with the eligible account and install Health Sync. TestFlight replaces
a development installation with the same bundle identifier; keep/export any
needed state first. Do not assume Keychain sessions and watermarks transfer
unchanged. Do not uninstall as a troubleshooting step without considering local
state. Drive exports remain independent of app installation.

On each device:
- Launch, connect Google, and approve only selected HealthKit read permissions.
- Sync a small selection, verify CSV values/UUIDs and manifests in your Drive.
- Run a second sync and check duplicate handling and watermark advancement.
- Exercise permission denial, revoked Google access and network interruption.
- Test the first backfill and a larger dataset while watching responsiveness.
- Test the Shortcuts intent while unlocked, plus locked-device failure behavior.
- Verify no health rows, CSV bodies or OAuth tokens appear in Sentry events.
- Confirm the iPad has Health data available/synced; installing the same app
  does not itself transfer the iPhone's Health database.

Keep testing owner-only while the 11 October watchdog termination remains
unresolved. Record device, OS, version/build, foreground/Shortcut/locked context
and dataset size. Retain the matching archive/dSYMs and inspect symbolicated
reports. Distribution is not evidence that the reliability issue is fixed.
Require a diagnosed/fixed watchdog issue and successful repeated device checks
before considering any wider beta.

## CI and future maintenance

GitHub Actions builds the shared scheme (including Swift package dependency
ordering) in Debug and Release on Xcode 26.3 without signing or OAuth secrets.
The previous target-only CI failed with missing AppAuthCore/GTMSessionFetcher
module maps; the scheme build addresses dependency orchestration. CI success
does not validate signing, archive export, HealthKit behavior or upload.

The initial maintained distribution workflow is local Mac script + explicit
owner-only selection. If recurring cloud distribution becomes worthwhile,
configure Xcode Cloud from Xcode, grant GitHub access deliberately, and select
**TestFlight (Internal Testing Only)** for its archive action. Keep its workflow
manual initially and store build configuration only in protected environment
secrets. Do not create a credential-bearing GitHub Actions upload workflow on
pull requests.

References:
- https://developer.apple.com/tutorials/develop-in-swift/test-your-beta-app
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers
- https://developer.apple.com/news/upcoming-requirements/?id=04282026a
- https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest

## Setup completed on 13 October 2026

App Store Connect record created: Apple ID 6822114620, SKU healthsync-personal,
English (Australia), existing bundle com.mattjamesaus.HealthSyncApp.
Apple rejected both "Health Sync" and "HealthSync" as unavailable names.
The device display name is HealthSync; the Connect record needs the unique
name HealthSync Personal. No build has been uploaded. Debug and Release CI
passed on Xcode 26.3 for the initial distribution workflow commit.
