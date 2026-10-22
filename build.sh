#!/bin/zsh
set -e
cd "${0:A:h}"
APP="build/KeyLightMenu.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library -target arm64-apple-macosx13.0 KeyLightMenu.swift -o "$APP/Contents/MacOS/KeyLightMenu"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
