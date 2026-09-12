#!/bin/bash
# Builds ShowMyBest.app.
#
# Xcode is not needed: the app is a SwiftPM executable wrapped in a bundle, so
# the Command Line Tools are enough (OI-5 — installed by copying the .app to
# /Applications, not through the App Store).
#
#   Tools/build-app.sh [debug|release]     default: release

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
APP="build/ShowMyBest.app"

swift build -c "$CONFIGURATION" --product ShowMyBest

BINARY="$(swift build -c "$CONFIGURATION" --product ShowMyBest --show-bin-path)/ShowMyBest"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/ShowMyBest"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Show My Best</string>
	<key>CFBundleDisplayName</key>
	<string>Show My Best</string>
	<key>CFBundleExecutable</key>
	<string>ShowMyBest</string>
	<key>CFBundleIdentifier</key>
	<string>com.csenkey.showmybest</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSSupportsAutomaticTermination</key>
	<true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run on this Mac, and it keeps the app's access to
# the photo folder stable across rebuilds.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc signing failed; the app will still run"

echo "built $APP"
