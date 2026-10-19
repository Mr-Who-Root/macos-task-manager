#!/usr/bin/env bash
# Installs the latest release of Task Manager for macOS.
#
#   curl -fsSL https://mr-who-root.github.io/macos-task-manager/install.sh | bash
#
# Options (environment variables):
#   INSTALL_DIR=/path   install somewhere other than /Applications
#   NO_OPEN=1           don't open the app afterwards
set -euo pipefail

REPO="Mr-Who-Root/macos-task-manager"
APP_NAME="Task Manager.app"
BASE_URL="https://github.com/$REPO/releases/latest/download"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

fail() { echo "Error: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Task Manager runs on macOS only."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 15 )) || fail "Task Manager needs macOS 15 or later (this Mac has $(sw_vers -productVersion))."

if [[ ! -d "$INSTALL_DIR" ]]; then
  mkdir -p "$INSTALL_DIR" 2>/dev/null || fail "Can't create $INSTALL_DIR."
fi
if [[ ! -w "$INSTALL_DIR" ]]; then
  echo "$INSTALL_DIR isn't writable; installing to ~/Applications instead."
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Downloading Task Manager…"
curl -fL --progress-bar "$BASE_URL/TaskManager.zip" -o "$workdir/TaskManager.zip" || fail "Download failed."
curl -fsSL "$BASE_URL/TaskManager.zip.sha256" -o "$workdir/TaskManager.zip.sha256" || fail "Couldn't download the checksum."

echo "Verifying checksum…"
expected="$(awk '{print $1}' "$workdir/TaskManager.zip.sha256")"
actual="$(shasum -a 256 "$workdir/TaskManager.zip" | awk '{print $1}')"
[[ -n "$expected" && "$expected" == "$actual" ]] || fail "Checksum mismatch. The download may be damaged; please try again."

ditto -x -k "$workdir/TaskManager.zip" "$workdir/unpacked"
[[ -d "$workdir/unpacked/$APP_NAME" ]] || fail "The download doesn't contain $APP_NAME."
codesign --verify --deep --strict "$workdir/unpacked/$APP_NAME" 2>/dev/null || fail "The app's code signature is invalid."

if pgrep -x TaskManager >/dev/null 2>&1; then
  echo "Quitting the running copy of Task Manager…"
  osascript -e 'quit app id "dev.taskmanager.mac"' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x TaskManager >/dev/null 2>&1 || break; sleep 0.5; done
fi

rm -rf "${INSTALL_DIR:?}/$APP_NAME"
mv "$workdir/unpacked/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
# Downloaded with curl, so there's normally no quarantine flag; clear it just in case.
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

version="$(defaults read "$INSTALL_DIR/$APP_NAME/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
echo "Installed Task Manager ${version:+$version }in $INSTALL_DIR."
echo "Press Control-Shift-Escape any time to bring it to the front."

if [[ "${NO_OPEN:-0}" != "1" ]]; then
  open "$INSTALL_DIR/$APP_NAME"
fi
