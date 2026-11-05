#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
VERSION="${VERSION:-$PLIST_VERSION}"
APP_NAME="Dropshake"
BUILD_DIR="$ROOT/.build"
ARM64_BUILD_DIR="$BUILD_DIR/universal-arm64"
X86_64_BUILD_DIR="$BUILD_DIR/universal-x86_64"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$ROOT/$APP_NAME-$VERSION.dmg"
RW_DMG="$BUILD_DIR/$APP_NAME-$VERSION-rw.dmg"
STAGING="$BUILD_DIR/$APP_NAME-dmg-staging"
MOUNT_POINT="$BUILD_DIR/$APP_NAME-dmg-mount"
BACKGROUND="$BUILD_DIR/dmg-background.png"
ICONSET="$BUILD_DIR/Dropshake.iconset"

command -v swift >/dev/null || { echo "Swift is required." >&2; exit 1; }
command -v hdiutil >/dev/null || { echo "Run this script on macOS." >&2; exit 1; }
command -v lipo >/dev/null || { echo "lipo is required to build a universal app." >&2; exit 1; }

cd "$ROOT"
swift build -c "$CONFIGURATION" --triple arm64-apple-macosx13.0 --scratch-path "$ARM64_BUILD_DIR"
swift build -c "$CONFIGURATION" --triple x86_64-apple-macosx13.0 --scratch-path "$X86_64_BUILD_DIR"
ARM64_BIN_DIR="$(swift build --show-bin-path -c "$CONFIGURATION" --triple arm64-apple-macosx13.0 --scratch-path "$ARM64_BUILD_DIR")"
X86_64_BIN_DIR="$(swift build --show-bin-path -c "$CONFIGURATION" --triple x86_64-apple-macosx13.0 --scratch-path "$X86_64_BUILD_DIR")"
lipo -create "$ARM64_BIN_DIR/$APP_NAME" "$X86_64_BIN_DIR/$APP_NAME" -output "$BUILD_DIR/$APP_NAME-universal"
echo "Universal binary: $(lipo -archs "$BUILD_DIR/$APP_NAME-universal")"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME-universal" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/Resources/Dropshake-icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$ROOT/Resources/Dropshake-icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi

rm -rf "$STAGING" "$MOUNT_POINT"
mkdir -p "$STAGING/.background" "$MOUNT_POINT"
cp -R "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
swift "$ROOT/scripts/create-dmg-background.swift" "$BACKGROUND"
cp "$BACKGROUND" "$STAGING/.background/background.png"
rm -f "$DMG" "$RW_DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDRW "$RW_DMG"
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT" "$RW_DMG" >/dev/null

osascript <<APPLESCRIPT
tell application "Finder"
    open (POSIX file "$MOUNT_POINT")
    delay 1
    set dmgWindow to front Finder window
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set bounds of dmgWindow to {120, 120, 1020, 720}
    set iconOptions to icon view options of dmgWindow
    set icon size of iconOptions to 160
    set text size of iconOptions to 14
    set arrangement of iconOptions to not arranged
    set background picture of iconOptions to POSIX file "$MOUNT_POINT/.background/background.png"
    set position of item "$APP_NAME.app" of dmgWindow to {225, 245}
    set position of item "Applications" of dmgWindow to {675, 245}
    delay 2
    close dmgWindow
end tell
APPLESCRIPT

sync
detached=false
for attempt in 1 2 3 4 5; do
  if hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1; then
    detached=true
    break
  fi
  sleep 2
done
if [[ "$detached" != true ]]; then
  echo "DMG is still busy; force detaching it." >&2
  hdiutil detach -force "$MOUNT_POINT" >/dev/null
fi
hdiutil convert "$RW_DMG" -ov -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW_DMG"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
echo "Created $DMG"
