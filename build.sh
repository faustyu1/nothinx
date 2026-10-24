#!/bin/zsh
# Builds Nothinx.app with its widget into ./build. Pass --install to copy it to /Applications.
# The Xcode project is generated from project.yml (brew install xcodegen). Signing uses the
# personal team 2C76W4D5L5; the widget needs its provisioning profile for the shared App Group.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
# A fresh build number each time; otherwise the widget gallery keeps showing cached widgets.
xcodebuild -project Nothinx.xcodeproj -scheme Nothinx -configuration Release \
  -derivedDataPath .build/xcode -allowProvisioningUpdates build -quiet \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)"
rm -rf build/Nothinx.app
mkdir -p build
cp -R .build/xcode/Build/Products/Release/Nothinx.app build/
echo "Built build/Nothinx.app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Nothinx || true
  rm -rf /Applications/Nothinx.app
  cp -R build/Nothinx.app /Applications/
  # Leave only the installed copy in LaunchServices, or the widget may bind to a stale build.
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -u "$PWD/build/Nothinx.app" "$PWD/.build/xcode/Build/Products/Release/Nothinx.app" 2>/dev/null || true
  "$LSREGISTER" -f /Applications/Nothinx.app
  open /Applications/Nothinx.app
  echo "Installed /Applications/Nothinx.app"
fi
