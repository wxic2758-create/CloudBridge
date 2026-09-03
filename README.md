# CloudBridge

CloudBridge is a first-pass macOS SFTP client for pulling files from cloud servers without Termius.

## Run

Build the app bundle:

```bash
./build-app.sh
```

Open:

```bash
open build/CloudBridge.app
```

## Current MVP

- Connect to an SFTP server by host, port, username, and password.
- Keeps the entered password only for the current app session.
- Browse remote folders.
- Double-click a folder to open it.
- Double-click a file to preview it with Quick Look.
- Choose the local download folder.

## Current Limitation

This MVP uses macOS `/usr/bin/ssh`, `/usr/bin/scp`, and `/usr/bin/sftp`, with password prompts routed through a local `SSH_ASKPASS` helper so it can build immediately without third-party dependencies. The build script now creates a sandboxed, signed app bundle, but a production App Store submission should still be tested carefully in a sandboxed clean-user environment.

See [AppStoreRelease.md](AppStoreRelease.md) for signing, packaging, and App Store Connect steps.
