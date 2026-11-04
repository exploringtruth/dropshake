# Dropshake

**A small, native macOS shelf for things you want to move later.** Park files in a floating window, switch to the destination, and drag them out when you are ready.

Dropshake is an independent project inspired by the general file-shelf workflow. It is not affiliated with Dropover and does not include Dropover code, artwork, or branding.

[Download Dropshake for macOS](https://github.com/exploringtruth/dropshake/releases/latest/download/Dropshake-0.2.17.dmg)

## What works today

- Native SwiftUI shelf window with a menu bar control.
- Shake the pointer while dragging to reveal a floating shelf beside the cursor.
- Dropshake keeps one current shelf. **Open Shelf** shows its current contents; shaking clears it and opens a completely empty shelf for the file being dragged.
- Drop files, folders, links, and plain text onto the shelf. Finder file URLs stay file references, preserving the original name and type.
- Capture file references, links, or text from the clipboard.
- Drag files and folders from the shelf into Finder or another app that accepts file drags; text and links can be dragged out as text.
- Click a card to select it, Command-click to toggle selection, or Shift-click to select a range; drag selected files together.
- After a successful file drop into another app, those files leave the shelf and the shelf window hides. Shaking again always starts with an empty shelf, without old shelf history or clipboard contents.
- Open items, reveal files in Finder, copy paths or text, and remove items from the shelf context menu.
- Preview files and folders with macOS Quick Look from the item context menu.
- Remove one item or clear the whole shelf.
- Remember shelf contents across launches using macOS bookmarks for file references, so moved files can often be located again; the shelf does not copy or upload the files.
- Move the floating shelf by dragging anywhere in its header.
- Resize the floating shelf from its edges or corners; its size is remembered between launches.
- Show horizontal, vertical, and diagonal resize cursors when hovering over shelf edges and corners.
- Drag files and folders out using native macOS file URL transfers, including files without a known extension.
- Display Finder icons, names, and file types.

Custom actions, image clipboard capture, and configurable global shortcuts remain future work.

## Requirements

- macOS 13 or newer
- Full Xcode installation with its Swift toolchain (the standalone Command Line Tools are not sufficient to build SwiftUI targets)
- `hdiutil` and `codesign` (included with macOS)

## Run from source

```sh
swift run
```

Dropshake runs from the menu bar. Choose **Open Shelf** there to show the current contents. Shake the pointer while dragging with the left mouse button held to clear those contents and open a completely empty shelf for the file being carried. Dropping files onto the shelf stores references without moving or copying the originals. Dragging files out transfers them to the destination, removes them from the shelf, and hides the shelf window.

Choose **Add Clipboard Contents** to add copied Finder files, links, or text to the current shelf.

## Build a DMG

On a Mac, from the project directory:

```sh
bash ./scripts/build-dmg.sh
```

This compiles a release build, creates `Dropshake.app` with the Dropshake app icon, and writes `Dropshake-0.2.17.dmg` in the project root. The DMG opens to a compact drag-to-install window with a clear arrow pointing to Applications. Override the version with `VERSION=1.0.0 bash ./scripts/build-dmg.sh`.

The default package is ad-hoc signed for local use. Since it is not signed with an Apple Developer ID or notarized, Gatekeeper may block the first launch on another Mac. For a public download that opens without that warning, sign and notarize the app with an Apple Developer ID certificate before sharing. Set `CODE_SIGN_IDENTITY` to that certificate's identity and `NOTARY_PROFILE` to a profile created with `xcrun notarytool store-credentials` when packaging. The script submits and staples the DMG when `NOTARY_PROFILE` is set.

## Publish a downloadable release

Push this project to a GitHub repository, then push a version tag:

```sh
git tag v0.2.17
git push origin v0.2.17
```

The GitHub Actions workflow builds a macOS DMG and attaches it to a GitHub Release. Releases produced by the included workflow are ad-hoc signed; configure Developer ID signing, notarization credentials, and certificate import in CI before sharing them as a polished public download. A private GitHub repository limits release downloads to people with repository access.

## Development

The app is a Swift Package so the shelf can be run with `swift run`. `Info.plist` contains the app bundle metadata, and `scripts/build-dmg.sh` turns the executable into a drag-to-install DMG layout.

## License

MIT. See [LICENSE](LICENSE).
