#!/bin/zsh
# Packages build/Nothinx.app for other Macs: drops the widget (its App Group needs the
# developer's own team signature), re-signs ad hoc and zips it into build/Nothinx.zip.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
OUT=build/release/Nothinx.app
rm -rf build/release build/Nothinx.zip
mkdir -p build/release
cp -R build/Nothinx.app "$OUT"
rm -rf "$OUT/Contents/PlugIns" "$OUT/Contents/embedded.provisionprofile"
codesign --force --sign - "$OUT/Contents/Frameworks/NothinxKit.framework"
codesign --force --sign - "$OUT"
codesign --verify --deep --strict "$OUT"
ditto -c -k --keepParent "$OUT" build/Nothinx.zip
echo "Packaged build/Nothinx.zip"
