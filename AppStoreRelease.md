# CloudBridge Mac App Store Release Checklist

This project can now build a sandboxed `.app` locally. To upload to App Store Connect, you still need Apple Developer account assets that cannot be generated from this repository.

## 1. Apple Developer Setup

1. Register the bundle identifier in Apple Developer:
   `com.dazhang.CloudBridge`
2. Enable the App Sandbox capability for the identifier.
3. Create a Mac App Store provisioning profile for that bundle ID.
4. Install signing certificates on this Mac:
   - Apple Distribution, or the current Mac App Store application signing identity shown in your Apple Developer account.
   - Mac Installer Distribution, or the current Mac App Store installer signing identity.

Check installed identities:

```bash
security find-identity -v -p codesigning
```

## 2. Build Locally

Local sandboxed ad-hoc build:

```bash
./build-app.sh
open build/CloudBridge.app
```

## 3. Build For App Store Upload

Preferred Xcode flow:

```bash
open CloudBridge.xcodeproj
```

Then use `Product > Archive`. This repository now includes a real macOS app project, so Xcode archives to:

```text
Products/Applications/CloudBridge.app
```

Command-line archive:

```bash
xcodebuild \
  -project CloudBridge.xcodeproj \
  -scheme CloudBridge \
  -destination 'generic/platform=macOS' \
  archive \
  -archivePath build/CloudBridge-Xcode.xcarchive
```

Export locally after Apple Distribution signing is available:

```bash
xcodebuild \
  -exportArchive \
  -archivePath build/CloudBridge-Xcode.xcarchive \
  -exportPath build/AppStoreExport \
  -exportOptionsPlist AppStoreExportOptions.plist \
  -allowProvisioningUpdates
```

Latest export result:

```text
build/AppStoreExport/CloudBridge.pkg
```

Upload to App Store Connect from the archive:

```bash
xcodebuild \
  -exportArchive \
  -archivePath build/CloudBridge-Xcode.xcarchive \
  -exportPath build/AppStoreUpload \
  -exportOptionsPlist AppStoreUploadOptions.plist \
  -allowProvisioningUpdates
```

Legacy script flow:

Replace the profile path and certificate names with the exact names from your machine:

```bash
APP_SIGN_IDENTITY="Apple Distribution: Your Name (TEAMID)" \
INSTALLER_SIGN_IDENTITY="Mac Installer Distribution: Your Name (TEAMID)" \
APPSTORE_PROFILE="/path/to/CloudBridge_App_Store.provisionprofile" \
BUNDLE_ID="com.dazhang.CloudBridge" \
APP_VERSION="1.0.0" \
BUILD_NUMBER="2" \
./build-app.sh
```

This creates:

```text
build/CloudBridge.app
build/CloudBridge.pkg
```

Upload `build/CloudBridge.pkg` with Transporter or App Store Connect tooling.

## 4. App Store Connect Metadata

Use `AppStoreConnectSubmissionInfo.md` as the filled submission source. Prepare these before review:

  - App name: CloudBridge: SFTP Transfer
  - Search positioning: SFTP file transfer, SSH remote download, macOS server file manager
- Category: Developer Tools
- Age rating
- Support URL
- Marketing URL, optional
- Privacy policy URL, using the published version of `PrivacyPolicy.md`
- Screenshots for macOS
- App privacy answers
- Encryption/export compliance answers

CloudBridge uses SSH/SFTP/SCP, so answer the encryption questions carefully. The current implementation uses Apple's system-provided macOS SSH/SFTP/SCP tooling and does not implement proprietary encryption, but you still need to complete the export compliance section in App Store Connect.

## 5. Review Risks To Test Before Submitting

- Sandboxed SSH/SFTP/SCP process launching must be tested on a clean Mac user account.
- Password login now uses a local `SSH_ASKPASS` helper instead of `/usr/bin/expect`; verify password auth works in a sandboxed archive build on a clean Mac user account.
- Passwords are cached only for the current app session and should not be written to Keychain or UserDefaults.
- A future production-grade version could replace shelling out to `/usr/bin/ssh`, `/usr/bin/scp`, and `/usr/bin/sftp` with an embedded SFTP library for tighter control over transport and review surface.

## 6. Validation Commands

```bash
codesign -dv --verbose=4 build/CloudBridge.app
codesign -d --entitlements :- build/CloudBridge.app
spctl --assess --type execute --verbose build/CloudBridge.app
pkgutil --check-signature build/CloudBridge.pkg
```
