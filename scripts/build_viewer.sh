#!/bin/sh
# Build "QLMarkdown Viewer" (Release) and install it in ~/Applications.
set -e
cd "$(dirname "$0")/.."
xcodebuild -project QLMarkdown.xcodeproj -scheme "QLMarkdown Viewer" -configuration Release -derivedDataPath build/viewer -quiet build
APP="build/viewer/Build/Products/Release/QLMarkdown Viewer.app"
test -d "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/"QLMarkdown Viewer.app"
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/QLMarkdown Viewer.app"
