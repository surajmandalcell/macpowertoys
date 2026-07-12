#!/bin/zsh
# Build PowerToys (throttled, machine stays responsive) and install to /Applications.
# Usage: ./scripts/install.sh [--test]
set -e
cd "$(dirname "$0")/.."

if [[ "$1" == "--test" ]]; then
  taskpolicy -c utility nice -n 10 xcodebuild test -project powertoys.xcodeproj \
    -scheme powertoys -destination 'platform=macOS' -jobs 4 \
    -only-testing:powertoysTests -skip-testing:powertoysUITests | grep -E "TEST (SUCCEEDED|FAILED)|error:"
fi

taskpolicy -c utility nice -n 10 xcodebuild -project powertoys.xcodeproj \
  -scheme powertoys -configuration Release -jobs 4 build | grep -E "BUILD (SUCCEEDED|FAILED)|error:"

PRODUCTS=$(xcodebuild -project powertoys.xcodeproj -scheme powertoys -configuration Release \
  -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')

# Quitting is safe: active transfers auto-pause and auto-resume on relaunch.
osascript -e 'tell application "powertoys" to quit' 2>/dev/null || true
sleep 3
rm -rf /Applications/PowerToys.app
ditto "$PRODUCTS/powertoys.app" /Applications/PowerToys.app
open /Applications/PowerToys.app
echo "Installed $(defaults read /Applications/PowerToys.app/Contents/Info.plist CFBundleShortVersionString) to /Applications"
