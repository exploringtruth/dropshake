# Releasing DropShake

When asked to publish a release, commit the intended changes on a clean branch based on `origin/main` and run `./scripts/release.sh` from that checkout. The script bumps the patch version and pushes the release commit and tag together. Pass an explicit version only when needed. GitHub Actions builds and publishes the release. Verify that the run succeeds and that the public appcast points at the new version before reporting the release as live. See [the updater guide](docs/UPDATER.md#publishing).
