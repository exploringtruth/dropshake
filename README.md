<p align="center">
  <img src="Resources/Dropshake-icon-rounded.png" width="128" alt="Dropshake app icon">
  <h1 align="center">Dropshake</h1>
  <p align="center">A temporary shelf for files you want to move later.</p>
  <p align="center">
    <a href="https://github.com/exploringtruth/dropshake/releases/latest"><img src="https://img.shields.io/github/v/release/exploringtruth/dropshake?label=release" alt="Latest release"></a>
    <a href="https://github.com/exploringtruth/dropshake/actions/workflows/release.yml"><img src="https://img.shields.io/github/actions/workflow/status/exploringtruth/dropshake/release.yml?label=build" alt="Build status"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/exploringtruth/dropshake?label=license" alt="GPL-3.0-or-later license"></a>
    <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="Requires macOS 13 or later">
  </p>
  <p align="center">
    <a href="https://github.com/exploringtruth/dropshake/releases/latest/download/Dropshake.dmg"><strong>Download the DMG</strong></a>
    &nbsp;·&nbsp;
    <a href="https://exploringtruth.github.io/dropshake/"><strong>Official website</strong></a>
  </p>
</p>

## Use Dropshake

1. Drag a file from Finder and shake your pointer to open a fresh shelf.
2. Drop the file onto the shelf while you switch to its destination.
3. Drag it from the shelf into Finder or another app. Select multiple items to move them together.

Use the menu bar icon to open the shelf or add files, links, and text from your clipboard.
Packaged releases check for updates automatically and show an install prompt when a new version is available. Choose **Check for Updates** in the menu bar to check immediately.

## Install

Download the [latest DMG](https://github.com/exploringtruth/dropshake/releases/latest/download/Dropshake.dmg), open it, drag **Dropshake** into **Applications**, then eject the **Dropshake** disk in Finder.

Requires macOS 13 or later. The app is currently ad-hoc signed, so macOS may ask you to confirm it the first time you open it.

### If macOS blocks Dropshake

Dropshake is currently not notarized by Apple. To approve it, follow these steps:

1. Open **Dropshake** once. When macOS shows the warning, click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security** and click **Open Anyway** next to the Dropshake warning.
4. Confirm **Open** in the dialog.
5. Look for the Dropshake icon in the menu bar to confirm the app is running.

You only need to approve the installed copy. macOS may ask again after you install a newly downloaded release. See [Apple’s instructions](https://support.apple.com/en-us/102445).

## Build from source

Requires Xcode and macOS.

```sh
swift run
```

To build the installer DMG:

```sh
bash ./scripts/build-dmg.sh
```

Dropshake is an independent project inspired by the file-shelf workflow.

## License

Dropshake is licensed under the GNU General Public License v3.0 or later ([GPL-3.0-or-later](LICENSE)).
