#!/bin/zsh
# Builds dist/快捷手势.app from source. Used by install.sh and the release workflow.
# Signs with an Apple Development certificate when one is available, otherwise ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/GesturePad"
APP="dist/快捷手势.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GesturePad"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${GESTUREPAD_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${GESTUREPAD_VERSION#v}" "$APP/Contents/Info.plist"
fi

IDENTITY="${GESTUREPAD_SIGN_IDENTITY:-$(security find-identity -p codesigning -v 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)"/\1/p' | head -1)}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --options runtime --timestamp=none "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --verbose=2 "$APP"
echo "built $APP"
