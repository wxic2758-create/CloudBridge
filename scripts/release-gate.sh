#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/CloudBridge.xcodeproj"
SCHEME="CloudBridge"
EXPECTED_VERSION="1.0"
EXPECTED_BUILD="17"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbridge-release-gate.XXXXXX")"
DERIVED_DATA="$WORK_DIR/DerivedData"
RESULT_BUNDLE="$WORK_DIR/CloudBridgeTests.xcresult"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
    printf 'Release gate failed: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

setting_values() {
    local key="$1"
    awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2 }' "$ROOT_DIR/CloudBridge.xcodeproj/project.pbxproj" \
        | sed 's/;[[:space:]]*$//' \
        | sort -u
}

printf 'CloudBridge release gate (no signing, archive, export, or upload)\n'
printf 'Temporary output: %s\n' "$WORK_DIR"

require_command python3
require_command git

cd "$ROOT_DIR"
printf '\n== Working tree (informational) ==\n'
git status --short

printf '\n== Static prerequisites ==\n'
[[ -f "$PROJECT/project.pbxproj" ]] || fail "missing Xcode project"
[[ -f "$PROJECT/xcshareddata/xcschemes/$SCHEME.xcscheme" ]] || fail "missing shared scheme"
[[ -f "$ROOT_DIR/PrivacyInfo.xcprivacy" ]] || fail "missing privacy manifest"
[[ -f "$ROOT_DIR/Tests/CloudBridgeTests/ProcessRunnerTests.swift" ]] || fail "missing Xcode/SwiftPM test source"
[[ -x "$ROOT_DIR/Resources/ssh-askpass.sh" ]] || fail "Resources/ssh-askpass.sh is not executable"
[[ "$(git ls-files -s Resources/ssh-askpass.sh | awk '{print $1}')" == "100755" ]] || fail "ssh-askpass.sh is not tracked with mode 100755"
grep -q '^#!/bin/sh$' "$ROOT_DIR/Resources/ssh-askpass.sh" || fail "ssh-askpass.sh has an unexpected shebang"
grep -q 'BlueprintName = "CloudBridgeTests"' "$PROJECT/xcshareddata/xcschemes/$SCHEME.xcscheme" || fail "shared scheme has no CloudBridgeTests testable"
grep -q 'productType = "com.apple.product-type.bundle.unit-test"' "$PROJECT/project.pbxproj" || fail "Xcode project has no unit-test target"
[[ "$(setting_values MARKETING_VERSION)" == "$EXPECTED_VERSION" ]] || fail "MARKETING_VERSION is not consistently $EXPECTED_VERSION"
[[ "$(setting_values CURRENT_PROJECT_VERSION)" == "$EXPECTED_BUILD" ]] || fail "CURRENT_PROJECT_VERSION is not consistently $EXPECTED_BUILD"
grep -q 'APP_VERSION="${APP_VERSION:-1.0}"' build-app.sh || fail "build-app.sh version does not match $EXPECTED_VERSION"
grep -q 'BUILD_NUMBER="${BUILD_NUMBER:-17}"' build-app.sh || fail "build-app.sh build does not match $EXPECTED_BUILD"
python3 scripts/check-localization.py

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    fail "Xcode is required for tests and unsigned build validation"
fi
require_command swift
require_command plutil

plutil -lint CloudBridge.entitlements PrivacyInfo.xcprivacy AppStoreExportOptions.plist AppStoreUploadOptions.plist
xcodebuild -list -project "$PROJECT"

printf '\n== SwiftPM tests and release build ==\n'
swift test --scratch-path "$WORK_DIR/swift-test"
swift build -c release --scratch-path "$WORK_DIR/swift-build"

printf '\n== Xcode unit tests ==\n'
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$RESULT_BUNDLE" \
    test \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

printf '\n== Unsigned Xcode Release build ==\n'
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    build \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

APP="$DERIVED_DATA/Build/Products/Release/CloudBridge.app"
ASKPASS="$APP/Contents/Resources/ssh-askpass.sh"
PRIVACY_MANIFEST="$APP/Contents/Resources/PrivacyInfo.xcprivacy"
[[ -d "$APP" ]] || fail "Release app was not produced"
askpass_files=()
while IFS= read -r path; do askpass_files+=("$path"); done < <(find "$APP/Contents/Resources" -name ssh-askpass.sh -type f)
[[ "${#askpass_files[@]}" -eq 1 ]] || fail "expected exactly one bundled ssh-askpass.sh, found ${#askpass_files[@]}"
[[ "${askpass_files[0]}" == "$ASKPASS" ]] || fail "ssh-askpass.sh is not at the resource root"
[[ -x "$ASKPASS" ]] || fail "bundled ssh-askpass.sh is not executable"
[[ ! -e "$APP/Contents/Resources/Resources/ssh-askpass.sh" ]] || fail "nested duplicate askpass resource exists"
[[ -f "$PRIVACY_MANIFEST" ]] || fail "privacy manifest was not bundled"
plutil -lint "$PRIVACY_MANIFEST"

locale_count="$(find "$APP/Contents/Resources" -maxdepth 1 -type d -name '*.lproj' | wc -l | tr -d ' ')"
[[ "$locale_count" -eq 36 ]] || fail "expected 36 bundled locale directories, found $locale_count"

bundle_version="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
bundle_build="$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")"
uses_non_exempt_encryption="$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$APP/Contents/Info.plist")"
[[ "$bundle_version" == "$EXPECTED_VERSION" ]] || fail "built app version is $bundle_version, expected $EXPECTED_VERSION"
[[ "$bundle_build" == "$EXPECTED_BUILD" ]] || fail "built app build is $bundle_build, expected $EXPECTED_BUILD"
[[ "$uses_non_exempt_encryption" == "false" ]] || fail "ITSAppUsesNonExemptEncryption is not false"

printf '\nRelease gate passed. Signing, archive, export, ASC upload, and GUI validation were intentionally not run.\n'
