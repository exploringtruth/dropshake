# Dropshake

**A small, native macOS shelf for things you want to move later.** Park files in a floating window, switch to the destination, and drag them out when you are ready.

Dropshake is an independent project inspired by the general file-shelf workflow. It is not affiliated with Dropover and does not include Dropover code, artwork, or branding.

## What works today

- Native SwiftUI shelf window with a menu bar control.
- Drop files, folders, links, and plain text onto the shelf.
- Drag files and folders from the shelf into Finder or another app that accepts file drags; text and links can be dragged out as text.
- Remove one item or clear the whole shelf.
- Remember shelf contents across launches. The shelf stores file references; it does not copy or upload the files.
- Display Finder icons, names, and file types.

The current starter focuses on the dependable shelf workflow. Shake-to-open while a drag is in progress, multiple named shelves, clipboard capture, actions, and configurable shortcuts are future work.

## Requirements

- macOS 13 or newer
- Swift 5.10 or newer
- Xcode command line tools for building
- `hdiutil` and `codesign` (included with macOS)

## Run from source

```sh
swift run
```

The app's window is the shelf. Use the Dropshake tray icon in the menu bar to bring it forward, clear its contents, or quit.

## Build a DMG

On a Mac, from the project directory:

```sh
./scripts/build-dmg.sh
```

This compiles a release build, creates `Dropshake.app`, and writes `Dropshake-0.1.0.dmg` in the project root. Override the version with `VERSION=1.0.0 ./scripts/build-dmg.sh`.

The default package is ad-hoc signed for local use. Since it is not signed with an Apple Developer ID or notarized, Gatekeeper may block the first launch on another Mac. For a public download that opens without that warning, sign and notarize the app with an Apple Developer ID certificate before sharing. Set `CODE_SIGN_IDENTITY` to that certificate's identity and `NOTARY_PROFILE` to a profile created with `xcrun notarytool store-credentials` when packaging. The script submits and staples the DMG when `NOTARY_PROFILE` is set.

## Publish a downloadable release

Push this project to a GitHub repository, then push a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The GitHub Actions workflow builds a macOS DMG and attaches it to a GitHub Release. Releases produced by the included workflow are ad-hoc signed; configure Developer ID signing, notarization credentials, and certificate import in CI before sharing them as a polished public download. A private GitHub repository limits release downloads to people with repository access.

## Development

The app is a Swift Package so the shelf can be run with `swift run`. `Info.plist` contains the app bundle metadata, and `scripts/build-dmg.sh` turns the executable into a drag-to-install DMG layout.

## License

MIT. See [LICENSE](LICENSE).
