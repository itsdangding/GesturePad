#!/bin/zsh
# Tests, builds and installs to ~/Applications/快捷手势.app, then opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test
./scripts/build-app.sh

APP="$HOME/Applications/快捷手势.app"
mkdir -p "$HOME/Applications"
killall GesturePad 2>/dev/null || true
rm -rf "$APP"
ditto "dist/快捷手势.app" "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
open "$APP"
echo "installed $APP"
