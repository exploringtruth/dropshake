#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if (( $# > 1 )); then
  echo "Usage: $0 [MAJOR.MINOR.PATCH]" >&2
  exit 1
fi

if ! git symbolic-ref --quiet HEAD >/dev/null || [[ -n "$(git status --porcelain)" ]]; then
  echo "Run this from a branch with a clean working tree and all release changes committed." >&2
  exit 1
fi

git fetch --tags origin main
if ! git merge-base --is-ancestor FETCH_HEAD HEAD; then
  echo "Update this branch to include origin/main before releasing." >&2
  exit 1
fi

version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
if [[ ! "$current_version" =~ $version_pattern ]]; then
  echo "Invalid version in Info.plist: $current_version" >&2
  exit 1
fi
IFS=. read -r current_major current_minor current_patch <<< "$current_version"
version="${1:-$current_major.$current_minor.$((current_patch + 1))}"
if [[ ! "$version" =~ $version_pattern ]]; then
  echo "Use a version in MAJOR.MINOR.PATCH format." >&2
  exit 1
fi
IFS=. read -r major minor patch <<< "$version"
if (( major < current_major ||
      (major == current_major && minor < current_minor) ||
      (major == current_major && minor == current_minor && patch <= current_patch) )); then
  echo "The new version must be newer than $current_version." >&2
  exit 1
fi

tag="v$version"
if git show-ref --verify --quiet "refs/tags/$tag"; then
  echo "Tag $tag already exists." >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $version" Info.plist
git add Info.plist
git commit -m "Release Dropshake $tag"
git tag -a "$tag" -m "Dropshake $tag"

if ! git push --atomic origin HEAD:refs/heads/main "refs/tags/$tag"; then
  echo "Release commit and tag $tag are local. Resolve the push error, then retry the same atomic push." >&2
  exit 1
fi

echo "Pushed $tag. The Build and publish DMG workflow will publish the release."
