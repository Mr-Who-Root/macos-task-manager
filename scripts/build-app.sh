#!/usr/bin/env bash
# Builds "Task Manager.app" into ./build.
#   scripts/build-app.sh            release build for this Mac's architecture
#   scripts/build-app.sh --universal  release build for Apple silicon + Intel
#   scripts/build-app.sh --install  also copies the app to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
    --install) INSTALL=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

echo "==> Compiling"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/Task Manager.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TaskManager" "$APP/Contents/MacOS/TaskManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Adding widget extension"
APPEX="$APP/Contents/PlugIns/TaskManagerWidgets.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp "$BIN_DIR/TaskManagerWidgets" "$APPEX/Contents/MacOS/TaskManagerWidgets"
cp Resources/Widgets-Info.plist "$APPEX/Contents/Info.plist"
# The extension's version must match the app's.
for key in CFBundleShortVersionString CFBundleVersion; do
  plutil -replace "$key" -string "$(plutil -extract "$key" raw Resources/Info.plist)" "$APPEX/Contents/Info.plist"
done

echo "==> Rendering icon"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Signing (ad hoc)"
# Sign the sandboxed extension first, then the app around it.
codesign --force --sign - --entitlements Resources/Widgets.entitlements "$APPEX"
codesign --force --sign - "$APP"

if [[ $INSTALL == 1 ]]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/Task Manager.app"
  cp -R "$APP" "/Applications/Task Manager.app"
fi

echo "Done: $APP"
