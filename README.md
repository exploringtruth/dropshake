# Dropshake

**A small, native macOS shelf for things you want to move later.** Park files in a floating window, switch to the destination, and drag them out when you are ready.

Dropshake is an independent project inspired by the general file-shelf workflow. It is not affiliated with Dropover and does not include Dropover code, artwork, or branding.

[Download Dropshake for macOS](https://github.com/exploringtruth/dropshake/releases/latest/download/Dropshake-0.2.4.dmg)

## What works today

- Native SwiftUI shelf window with a menu bar control.
- Shake the pointer while dragging to reveal a floating shelf beside the cursor.
- Create, switch, rename, delete, and clear multiple persistent shelves.
- Drop files, folders, links, and plain text onto the shelf.
- Capture file references, links, or text from the clipboard.
- Drag files and folders from the shelf into Finder or another app that accepts file drags; text and links can be dragged out as text.
- Open items, reveal files in Finder, copy paths or text, and remove items from the shelf context menu.
- Preview files and folders with macOS Quick Look from the item context menu.
- Remove one item or clear the whole shelf.
- Remember shelf contents across launches using macOS bookmarks for file references, so moved files can often be located again; the shelf does not copy or upload the files.
- Move the floating shelf by dragging its background.
- Display Finder icons, names, and file types.

Custom actions, image clipboard capture, and configurable global shortcuts remain future work.

## Requirements

- macOS 13 or newer
- Swift 5.10 or newer
- Xcode command line tools for building
- `hdiutil` and `codesign` (included with macOS)

## Run from source

```sh
swift run
```

Dropshake runs from the menu bar. Choose **Open Shelf** there, or shake the pointer while dragging with the left mouse button held. The floating shelf stays open until you hide it; dropping files onto it stores references without moving or copying the originals.

## Build a DMG

On a Mac, from the project directory:

```sh
bash ./scripts/build-dmg.sh
```

This compiles a release build, creates `Dropshake.app`, and writes `Dropshake-0.2.4.dmg` in the project root. Override the version with `VERSION=1.0.0 bash ./scripts/build-dmg.sh`.

The default package is ad-hoc signed for local use. Since it is not signed with an Apple Developer ID or notarized, Gatekeeper may block the first launch on another Mac. For a public download that opens without that warning, sign and notarize the app with an Apple Developer ID certificate before sharing. Set `CODE_SIGN_IDENTITY` to that certificate's identity and `NOTARY_PROFILE` to a profile created with `xcrun notarytool store-credentials` when packaging. The script submits and staples the DMG when `NOTARY_PROFILE` is set.

## Publish a downloadable release

Push this project to a GitHub repository, then push a version tag:

```sh
git tag v0.2.4
git push origin v0.2.4
```

The GitHub Actions workflow builds a macOS DMG and attaches it to a GitHub Release. Releases produced by the included workflow are ad-hoc signed; configure Developer ID signing, notarization credentials, and certificate import in CI before sharing them as a polished public download. A private GitHub repository limits release downloads to people with repository access.

## Development

The app is a Swift Package so the shelf can be run with `swift run`. `Info.plist` contains the app bundle metadata, and `scripts/build-dmg.sh` turns the executable into a drag-to-install DMG layout.

## License

MIT. See [LICENSE](LICENSE).
