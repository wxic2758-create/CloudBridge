# CloudBridge Release Checklist

## Local release candidate

- Bundle identifier: `com.dazhang.CloudBridge`
- Marketing version: `1.0`
- Build number: `17`
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

## Release candidate record — 2026-09-15

Prepared `CloudBridge 0.1.0 (14)` from Git commit `f45cca9` plus the intentional
local build-number and screenshot-generator changes:

- `bash scripts/release-gate.sh` passed for build 14: localization parity,
  SwiftPM tests, Xcode unit tests, SwiftPM Release build, and unsigned Xcode
  Release build all succeeded.
- Signed archive: `build/release/CloudBridge-0.1.0-14.xcarchive`.
- Exported package: `build/release/CloudBridge-0.1.0-14-export/CloudBridge.pkg`.
- The exported app is universal (`arm64` and `x86_64`), Apple Distribution
  signed for team `U9UPA9QQ7Y`, uses bundle ID `com.dazhang.CloudBridge`, and
  embeds the matching Mac App Store provisioning profile.
- The exported installer package is signed with the team's 3rd Party Mac
  Developer Installer certificate.
- The exported app contains the expected sandbox/network/file entitlements,
  `PrivacyInfo.xcprivacy`, one executable `ssh-askpass.sh`, and 36 locale bundles.
- Final English App Store screenshots are in
  `/Users/user/Desktop/CloudBridge-展示图截图/AppStore成品` as four 2880×1800 RGB
  PNG files.
- Transporter delivered `CloudBridge 0.1.0 (14)` to App Store Connect on
  September 15, 2026 at 11:44 CST with no errors. App Store ID: `6787467520`.
  Delivery UUID: `3a63f855-4b91-4054-b77f-fdd38b5f34cd`. Apple accepted
  4,201,654 bytes and reported the build as processing.

Remote items still to verify in App Store Connect before submission:

- Existing app record and whether any prior build 13 delivery exists. Build 14
  was selected locally to avoid reuse regardless of that result.
- Metadata, support/privacy URLs, app privacy, age rating, price, territories,
  export compliance, review notes, build selection, and release timing.
- Complete real-server smoke testing and decide whether draft localizations should
  be exposed in the first release.
- Reconcile and commit the heavily modified working tree so the release source is
  reproducible. Do not archive from an accidental mix of staged and untracked files.

## Final regression record — 2026-09-15

Regression was run against the archived `CloudBridge 0.1.0 (14)` application:

- The release gate passed again, including localization parity, SwiftPM tests,
  Xcode unit tests, both Release builds, property-list validation, and privacy-
  manifest validation.
- Xcode static analysis completed with `ANALYZE SUCCEEDED`.
- A saved real SFTP server connected without a Keychain prompt. Remote browsing,
  folder navigation, search, clear-search, refresh, Quick Look, download completion,
  download history, and Finder reveal all passed.
- Transporter now reports the delivered build as available for internal testing.
- Repeated downloads use collision-safe filename renaming; they do not show the
  duplicate-download warning currently described by the README and privacy text.

Submission is not yet cleared:

- The inferred GitHub Pages home, support, and privacy URLs return HTTP 404; live
  public URLs must be confirmed before submission.
- App Store Connect metadata and declarations still require an authenticated review.
- Several of the 36 exposed localizations still contain English draft values.
- Private-key/passphrase authentication was not exercised in this smoke test.
- The duplicate-download documentation must be aligned with the actual auto-rename
  behavior, and the release source changes should be committed for reproducibility.

## Password-only release candidate — 2026-09-15

Prepared `CloudBridge 0.1.0 (15)` after hiding private-key authentication from the
first-release interface:

- The add/edit server form now labels the credential as `Server password`; its
  advanced section exposes only display name, port, and starting folder.
- The in-app privacy explanation and public support/privacy copy now describe only
  password authentication. Duplicate-download documentation now matches the actual
  collision-safe auto-rename behavior.
- GUI validation confirmed that no private-key selector appears in the basic or
  expanded server editor.
- `bash scripts/release-gate.sh` passed: 36-locale key parity, 57 SwiftPM tests,
  Xcode unit tests, SwiftPM Release build, and universal unsigned Xcode Release build.
- Signed archive: `build/release/CloudBridge-0.1.0-15.xcarchive`.
- Exported package: `build/release/CloudBridge-0.1.0-15-export/CloudBridge.pkg`.
- The exported package contains an Apple Distribution-signed universal app for team
  `U9UPA9QQ7Y`, bundle ID `com.dazhang.CloudBridge`, version `0.1.0 (15)`, with the
  required entitlements, privacy manifest, and 36 locale bundles. The installer is
  signed with the team's 3rd Party Mac Developer Installer certificate.
- Package SHA-256: `94e931a855e93c8780396338d4cdd8571bc68a18c0f56441c165672af220ca9f`.
- Transporter recognizes build 15 and shows it as ready to deliver. Delivery has not
  started: the Transporter content button was unavailable to accessibility automation,
  and the Xcode upload fallback could not use an App Store Connect account.

## App Store 1.0 release candidate — 2026-09-15

Prepared `CloudBridge 1.0 (16)` as the first public release candidate:

- The marketing version is now `1.0`; build number `16` is unique and supersedes the
  unsubmitted `0.1.0 (15)` package.
- The app invokes only macOS-provided `/usr/bin/ssh` and `/usr/bin/sftp` for encrypted
  transport. `ITSAppUsesNonExemptEncryption` is set to `false` in the generated bundle
  so App Store Connect can recognize the exempt-encryption declaration.
- `bash scripts/release-gate.sh` passed: 36-locale key parity, 57 SwiftPM tests,
  Xcode unit tests, SwiftPM Release build, and universal unsigned Xcode Release build.
- Signed archive: `build/release/CloudBridge-1.0-16.xcarchive`.
- Exported package: `build/release/CloudBridge-1.0-16-export/CloudBridge.pkg`.
- The exported app is universal (`arm64` and `x86_64`), Apple Distribution signed for
  team `U9UPA9QQ7Y`, uses bundle ID `com.dazhang.CloudBridge`, and reports version
  `1.0 (16)` with `ITSAppUsesNonExemptEncryption = false`.
- The installer package is signed with the team's 3rd Party Mac Developer Installer
  certificate. Package SHA-256:
  `d90fec23a208aa64f877e33118ea81973ac613c1dd6aeb176f3734a3ddedf737`.

## App Store build 17 — 2026-09-15

Uploaded `CloudBridge 1.0 (17)` after the download-task interaction and initial
large-file progress improvements:

- `bash scripts/release-gate.sh` passed, including 58 SwiftPM tests, Xcode unit
  tests, localization parity for 36 locales, and the universal Release build.
- Signed archive: `build/release/CloudBridge-1.0-17.xcarchive`.
- Exported package: `build/release/CloudBridge-1.0-17-export/CloudBridge.pkg`.
- The package contains an Apple Distribution-signed universal app for team
  `U9UPA9QQ7Y`, bundle ID `com.dazhang.CloudBridge`, version `1.0 (17)`, with
  the expected sandbox entitlements, privacy manifest, and exempt-encryption declaration.
- Package SHA-256:
  `ed1e75ce0f02d7d6e38315a848ef232cd077f13acdb44a899151513202179faf`.
- Transporter delivered the build to App Store Connect at 16:44 CST. App Store
  ID: `6787467520`. Apple reports the build as processing.
