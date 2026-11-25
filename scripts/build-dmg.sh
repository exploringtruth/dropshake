#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
VERSION="${VERSION:-$PLIST_VERSION}"
APP_NAME="Dropshake"
BUILD_DIR="$ROOT/.build"
UNIVERSAL_BUILD_DIR="$BUILD_DIR/universal"
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
# Swift Build looks for package resource bundles in Contents/Resources.
SWIFT_BUILD_ARGS=(--build-system swiftbuild --arch arm64 --arch x86_64 -c "$CONFIGURATION" --scratch-path "$UNIVERSAL_BUILD_DIR")
swift build "${SWIFT_BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
ARCHITECTURES="$(lipo -archs "$BIN_DIR/$APP_NAME")"
case "$ARCHITECTURES" in
  'x86_64 arm64'|'arm64 x86_64') echo "Universal binary: $ARCHITECTURES" ;;
  *) echo "Expected an arm64 and x86_64 binary, got: $ARCHITECTURES" >&2; exit 1 ;;
esac
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
for resource_bundle in Dropshake_DropshakeApp.bundle KeyboardShortcuts_KeyboardShortcuts.bundle; do
  if [[ ! -d "$BIN_DIR/$resource_bundle" ]]; then
    echo "Missing Swift package resource bundle: $BIN_DIR/$resource_bundle" >&2
    exit 1
  fi
  cp -R "$BIN_DIR/$resource_bundle" "$APP/Contents/Resources/"
done
SPARKLE_FRAMEWORK="$(find "$BUILD_DIR" -type d -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -print -quit)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework was not found in $BUILD_DIR; resolve the Sparkle package first." >&2
  exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c 'Add :SUFeedURL string https://github.com/exploringtruth/dropshake/releases/latest/download/appcast.xml' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool true' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SUAllowsAutomaticUpdates bool false' "$APP/Contents/Info.plist"
fi
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
