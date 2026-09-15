#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_NAME="${APP_NAME:-CloudBridge}"
BUNDLE_ID="${BUNDLE_ID:-com.dazhang.CloudBridge}"
APP_VERSION="${APP_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-18}"
APP_CATEGORY="${APP_CATEGORY:-public.app-category.developer-tools}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
APPSTORE_PROFILE="${APPSTORE_PROFILE:-}"
ENTITLEMENTS_FILE="${ENTITLEMENTS_FILE:-$ROOT_DIR/CloudBridge.entitlements}"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PKG_PATH="${PKG_PATH:-$ROOT_DIR/build/$APP_NAME.pkg}"

cd "$ROOT_DIR"
# Prefer managed Python environment with Pillow installed
if [[ -x "/Users/user/.workbuddy/binaries/python/envs/default/bin/python3" ]]; then
    PYTHON="/Users/user/.workbuddy/binaries/python/envs/default/bin/python3"
else
    PYTHON="python3"
fi
"$PYTHON" "$ROOT_DIR/scripts/generate-icon.py"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/CloudBridge" "$MACOS_DIR/$APP_NAME"
iconutil -c icns "$ROOT_DIR/Assets/CloudBridge.iconset" -o "$RESOURCES_DIR/CloudBridge.icns"
cp "$ROOT_DIR/Resources/ssh-askpass.sh" "$RESOURCES_DIR/ssh-askpass.sh"
cp "$ROOT_DIR/PrivacyInfo.xcprivacy" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
chmod 755 "$RESOURCES_DIR/ssh-askpass.sh"
[[ -x "$RESOURCES_DIR/ssh-askpass.sh" ]] || { echo "ssh-askpass.sh is not executable" >&2; exit 1; }
for locale_dir in "$ROOT_DIR"/Resources/*.lproj; do
    [[ -d "$locale_dir" ]] || continue
    cp -R "$locale_dir" "$RESOURCES_DIR/"
done

if [[ -n "$APPSTORE_PROFILE" ]]; then
    cp "$APPSTORE_PROFILE" "$CONTENTS_DIR/embedded.provisionprofile"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>__APP_NAME__</string>
    <key>CFBundleIconFile</key>
    <string>CloudBridge.icns</string>
    <key>CFBundleIdentifier</key>
    <string>__BUNDLE_ID__</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>__APP_NAME__</string>
    <key>CFBundleDisplayName</key>
    <string>CloudBridge: SFTP Transfer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>__APP_VERSION__</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleVersion</key>
    <string>__BUILD_NUMBER__</string>
    <key>LSApplicationCategoryType</key>
    <string>__APP_CATEGORY__</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 CloudBridge. All rights reserved.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>CloudBridge uses your local network only when you connect to an SSH/SFTP server on your local network.</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
</dict>
</plist>
PLIST

"$PYTHON" - "$CONTENTS_DIR/Info.plist" "$APP_NAME" "$BUNDLE_ID" "$APP_VERSION" "$BUILD_NUMBER" "$APP_CATEGORY" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
replacements = {
    "__APP_NAME__": sys.argv[2],
    "__BUNDLE_ID__": sys.argv[3],
    "__APP_VERSION__": sys.argv[4],
    "__BUILD_NUMBER__": sys.argv[5],
    "__APP_CATEGORY__": sys.argv[6],
}
contents = path.read_text()
for key, value in replacements.items():
    contents = contents.replace(key, value)
path.write_text(contents)
PY

codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_FILE" --sign "$APP_SIGN_IDENTITY" "$APP_DIR" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null

echo "Built $APP_DIR"

if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
    rm -f "$PKG_PATH"
    productbuild --component "$APP_DIR" /Applications --sign "$INSTALLER_SIGN_IDENTITY" "$PKG_PATH" >/dev/null
    echo "Built $PKG_PATH"
fi
