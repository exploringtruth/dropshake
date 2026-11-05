# Maintainer setup: Sparkle updates

Dropshake embeds Sparkle in the app. Users do not install Sparkle separately. The first updater-enabled release must be installed manually; later releases can be installed from **Get Latest Version**.

## Create the signing key once

On a Mac with this repository checked out, resolve the package and create a key in your login Keychain:

```sh
cd ~/Documents/projects/dropshake
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dropshake
```

Keep the printed public key. The private key stays in Keychain. Export a protected copy for GitHub Actions:

```sh
umask 077
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dropshake -x /tmp/dropshake-sparkle-private-key
```

In the GitHub repository, open **Settings → Secrets and variables → Actions** and add:

- Repository variable `SPARKLE_PUBLIC_ED_KEY` with the printed public key.
- Repository secret `SPARKLE_PRIVATE_ED_KEY` with the contents of `/tmp/dropshake-sparkle-private-key`.

Delete the exported file after saving the secret:

```sh
rm /tmp/dropshake-sparkle-private-key
```

Never commit, paste into an issue, or print the private key in a workflow log. Keep the Keychain copy backed up securely; losing it means existing installs cannot verify future update feeds.

## Publishing

Tag and push a release as usual. The release workflow embeds the public key and appcast URL in the app, packages a ZIP for Sparkle, signs the update feed with the Actions secret, and uploads `appcast.xml` plus the ZIP and DMGs to the GitHub release. The public feed URL is the latest release's `appcast.xml` asset.

If either Actions setting is missing, the workflow stops before publishing. For ad-hoc builds, Sparkle cannot remove macOS Gatekeeper warnings; Apple Developer ID signing and notarization are separate from Sparkle update signing.
