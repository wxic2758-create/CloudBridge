# CloudBridge US App Store Listing

Use this as the final source of truth for the US App Store submission.

## Version

- Version: 0.1.0
- Build: 4
- Availability: United States only
- Price: Free

## English (US) Metadata

### Subtitle

SFTP Server File Manager

### Promotional Text

Connect to your own SSH/SFTP server, browse remote files, preview documents with Quick Look, and download folders. Passwords are kept only for the current app session.

### Description

CloudBridge is a lightweight macOS SFTP and SSH file transfer client for developers, operators, and power users who need a simple way to browse files on their own cloud servers.

Enter your server IP address or host name, username, and password to connect over SFTP. Browse remote folders, inspect file details, preview files with Quick Look, and download files or folders to a local directory.

Features:
- Connect to user-provided SFTP/SSH servers
- Password-based SFTP connection
- Session-only password cache
- Browse remote server folders
- Preview files with Quick Look
- Download files and folders
- Show directory size as - to avoid misleading fixed-size values

CloudBridge is not a cloud storage service. It does not send your server address, username, password, or file contents to the developer. You choose and control the servers you connect to.

### Keywords

SFTP file transfer,SSH download manager,remote server files,macOS file download,server preview

## What's New

Initial release of CloudBridge for macOS: connect to your own SFTP server, browse remote folders, preview files with Quick Look, and download files or folders.

## App Review Information

### Sign-in Required

No.

### Demo Account

No demo account is required. CloudBridge connects only to SSH/SFTP servers provided by the user.

### Review Notes

CloudBridge is a macOS SFTP client. It does not include a hosted backend or developer-operated server. Users enter their own server IP/host, port, username, password, and remote path.

The app can be reviewed without a developer-provided account by using any standard SSH/SFTP test server owned by the reviewer. CloudBridge does not store passwords in Keychain or UserDefaults; the entered password remains only in the current app session and is used to establish the user-requested SSH/SFTP connection.

Double-clicking a remote file downloads a temporary preview copy and opens it with macOS Quick Look. Explicit downloads are saved to the user-selected local download folder.

Network access is used only to connect to user-provided SSH/SFTP servers.

## App Privacy

Answer: Data Not Collected.

CloudBridge does not collect data for the developer, does not use analytics, does not use ads, does not use tracking, and does not send user data to a developer backend. Passwords are not stored persistently and are transmitted only to the user-specified SSH/SFTP server to establish a connection.

## Export Compliance

Status in App Store Connect: complete again for build 0.1.0 (2) after the new build is selected in the version page.

Selected answer:
- The app does not use proprietary encryption, custom non-standard encryption, or encryption beyond system-provided standard SSH/SFTP behavior.

## Screenshots

Upload these four Mac screenshots:
- /Users/user/Documents/CloudBridge/AppStoreScreenshots/01-connect.png
- /Users/user/Documents/CloudBridge/AppStoreScreenshots/02-saved-servers.png
- /Users/user/Documents/CloudBridge/AppStoreScreenshots/03-browser.png
- /Users/user/Documents/CloudBridge/AppStoreScreenshots/04-preview.png

All are 2880 x 1800.

## Still Needed From Developer

- Valid App Review phone number in international format. App Store Connect rejected the visible account number `16967282144`, `+8616967282144`, and `+16967282144`.
- Final manual confirmation before submitting for App Review.

## Current App Store Connect Status

- Latest build uploaded: 0.1.0 (5). App Store Connect is processing the package.
- Build attachment still needs to be updated in the App Store Connect version page after build 0.1.0 (5) finishes processing.
- App icon is included in the uploaded build asset catalog.
- Export compliance completed.
- Screenshots regenerated locally after the simplified UI update; upload the refreshed screenshots before final review submission.
- Availability: United States only.
- Price: Free.
- Release mode: manual release selected.
- Review login required: unchecked.
- Review notes: filled.
- Blocking before submission: valid review phone number and selecting build 0.1.0 (5) once processing finishes.

## Regression Check

- `xcodebuild -project CloudBridge.xcodeproj -scheme CloudBridge -configuration Release -destination 'platform=macOS' build`: passed.
- `xcodebuild -project CloudBridge.xcodeproj -scheme CloudBridge -destination 'generic/platform=macOS' archive -archivePath build/CloudBridge-MVP-0.1.0-3-20260810205923.xcarchive`: passed.
- `xcodebuild -exportArchive -archivePath build/CloudBridge-MVP-0.1.0-3-20260810205923.xcarchive -exportPath build/AppStoreUpload-0.1.0-3 -exportOptionsPlist AppStoreUploadOptions.plist -allowProvisioningUpdates`: uploaded successfully.
- Real SSH/SFTP regression harness: passed key authentication, remote directory listing, Quick Look preview download, file download, folder download, saved-auth state, and password/key cleanup logic.
- `xcodebuild -project CloudBridge.xcodeproj -scheme CloudBridge -configuration Debug -destination 'platform=macOS' build`: passed.
- `xcodebuild -project CloudBridge.xcodeproj -scheme CloudBridge -configuration Release -destination 'platform=macOS' build`: passed.
