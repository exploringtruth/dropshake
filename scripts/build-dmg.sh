#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.2.9}"
APP_NAME="Dropshake"
BUILD_DIR="$ROOT/.build"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$ROOT/$APP_NAME-$VERSION.dmg"

command -v swift >/dev/null || { echo "Swift is required." >&2; exit 1; }
command -v hdiutil >/dev/null || { echo "Run this script on macOS." >&2; exit 1; }

cd "$ROOT"
swift build -c "$CONFIGURATION"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$CONFIGURATION/Dropshake" "$APP/Contents/MacOS/Dropshake"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
echo "Created $DMG"
