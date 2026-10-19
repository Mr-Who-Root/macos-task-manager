#!/usr/bin/env bash
# Publishes a GitHub release for the version in Resources/Info.plist.
#
#   1. Bump CFBundleShortVersionString (and CFBundleVersion) on dev, open a PR, merge to main.
#   2. On an up-to-date main:  scripts/release.sh [notes.md]
#
# Builds a universal app, zips it as TaskManager.zip with a SHA-256 checksum, tags vX.Y.Z,
# pushes the tag and creates the release. The in-app updater and the website both download
# TaskManager.zip from the latest release, so the asset names must not change.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTES_FILE="${1:-}"
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
TAG="v$VERSION"

[[ "$(git branch --show-current)" == "main" ]] || { echo "Release from the main branch." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "The working tree has uncommitted changes." >&2; exit 1; }
git fetch origin main --tags --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "main is not in sync with origin/main." >&2; exit 1; }
if git rev-parse "$TAG" >/dev/null 2>&1; then echo "$TAG already exists. Bump the version first." >&2; exit 1; fi

./scripts/build-app.sh --universal

echo "==> Packaging"
rm -f build/TaskManager.zip build/TaskManager.zip.sha256
ditto -c -k --keepParent "build/Task Manager.app" build/TaskManager.zip
(cd build && shasum -a 256 TaskManager.zip > TaskManager.zip.sha256)
cat build/TaskManager.zip.sha256

echo "==> Tagging $TAG"
git tag -a "$TAG" -m "Task Manager $VERSION"
git push origin "$TAG"

echo "==> Creating release"
NOTES_ARGS=(--generate-notes)
[[ -n "$NOTES_FILE" ]] && NOTES_ARGS=(--notes-file "$NOTES_FILE")
gh release create "$TAG" build/TaskManager.zip build/TaskManager.zip.sha256 \
  --verify-tag --latest --title "Task Manager $VERSION" "${NOTES_ARGS[@]}"
