# CloudBridge Release Checklist

## Local release candidate

- Bundle identifier: `com.dazhang.CloudBridge`
- Marketing version: `0.1.0`
- Build number: `13`
- Minimum macOS version: `14.0`
- Category: Productivity
- App icon source: `Assets/IconComposer/CloudBridge-Purple.icon`

The local release gate currently passes SwiftPM tests, Xcode unit tests, SwiftPM Release
build, and unsigned Xcode Release build validation:

```sh
bash scripts/release-gate.sh
```

The manually packaged app can be built and verified with:

```sh
./build-app.sh
codesign --verify --deep --strict --verbose=2 build/CloudBridge.app
```

## Before submission

- Test password authentication against a real SFTP server.
- Test SSH private-key authentication, including a passphrase-protected key.
- Verify first-connection trust-on-first-use recording and changed-host-key blocking.
- Verify file and folder downloads, cancellation, retry, Finder reveal, and Quick Look.
- Capture final Mac App Store screenshots from the current build in both the empty and connected states.
- Add the final support URL and privacy policy URL in App Store Connect.
- Complete App Store Connect age rating, pricing, availability, export compliance, and privacy answers.
- Confirm the app record uses the same bundle identifier and team as the archive.
- Archive and export with the configured Apple Distribution signing identity.
- Upload the exported archive, wait for processing, select the exact build, and submit for review.

Signing, archive export, App Store Connect upload, and review submission are intentionally
not performed by the local release gate.

## Preflight record — 2026-09-14

Verified locally for `CloudBridge 0.1.0 (13)`:

- `bash scripts/release-gate.sh` passed after the direct-authentication and host-key
  handling fix. The current source passes 51 SwiftPM tests and a signed local Release
  app build.
- Xcode static analysis and a second unsigned Release build passed.
- Bundle ID `com.dazhang.CloudBridge`, team `U9UPA9QQ7Y`, macOS 14 minimum,
  App Sandbox, Hardened Runtime, and required file/network entitlements are consistent.
- Valid Apple Distribution and Mac App Store installer identities are installed.
- The matching Mac App Store provisioning profile expires September 4, 2027.
- `PrivacyInfo.xcprivacy` now declares the app's UserDefaults and system-uptime
  Required Reason API use and is present in the built app bundle.
- Simplified Chinese and Arabic RTL settings/download screens were smoke-tested from
  the Release app; Arabic layout mirrored correctly without visible overlap.
- The newest historical export proves the signing/export path can produce a universal,
  Apple Distribution-signed `CloudBridge.pkg`, but it predates the privacy-manifest fix.

Still required before upload:

- Smoke-test the completed download workflow against a real server: numeric progress,
  completed/failed states with retry, clear-history action beside the title, stable-width
  task badge, file-type icons, and multi-selection with sequential downloads are now
  implemented and covered by local state/model tests.
- Create and verify a fresh signed archive/export from the final committed source.
- Confirm in App Store Connect whether build 13 has ever been uploaded. If it has,
  increment `CURRENT_PROJECT_VERSION` and the matching script constants before archiving.
- Complete real-server smoke tests for password and private-key login, host-key handling,
  browsing, preview, file/folder download, cancellation, retry, and Finder reveal.
- Capture current Mac App Store screenshots; the previous screenshot set is absent from
  the working tree.
- Validate App Store Connect metadata, support/privacy URLs, privacy answers, age rating,
  pricing, territories, export compliance, and release timing.
- Finish translation review before presenting all 36 language choices as release-ready.
  Key parity passes, but many locale bundles still contain English draft values.
- Reconcile and commit the heavily modified working tree so the release source is
  reproducible. Do not archive from an accidental mix of staged and untracked files.
