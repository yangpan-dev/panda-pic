#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DIST_DIR="$PROJECT_ROOT/output/releases/v$RELEASE_VERSION"
APP_ROOT="$PROJECT_ROOT/output/distribution"
APP_PATH="$APP_ROOT/熊猫图库.app"
mkdir -p "$DIST_DIR"
bash "$PROJECT_ROOT/scripts/build-app.sh" release universal "$APP_ROOT"

DMG_STAGING="$(mktemp -d "$PROJECT_ROOT/.build/dmg-root.XXXXXX")"
trap 'rm -rf "$DMG_STAGING"' EXIT
ditto "$APP_PATH" "$DMG_STAGING/熊猫图库.app"
ln -s /Applications "$DMG_STAGING/Applications"
cp "$PROJECT_ROOT/docs/INSTALL.md" "$DMG_STAGING/下载安装教程.md"

ZIP_PATH="$DIST_DIR/PandaGallery-macOS-universal.zip"
DMG_PATH="$DIST_DIR/PandaGallery-macOS-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create -volname "熊猫图库 $RELEASE_VERSION" -srcfolder "$DMG_STAGING" -ov -format UDZO -imagekey zlib-level=9 "$DMG_PATH"
cp "$PROJECT_ROOT/docs/INSTALL.md" "$DIST_DIR/INSTALL-zh-CN.md"

codesign --verify --all-architectures --deep --strict "$APP_PATH"
lipo "$APP_PATH/Contents/MacOS/PandaGallery" -verify_arch arm64
lipo "$APP_PATH/Contents/MacOS/PandaGallery" -verify_arch x86_64
unzip -tq "$ZIP_PATH"
hdiutil verify "$DMG_PATH"
(
  cd "$DIST_DIR"
  shasum -a 256 PandaGallery-macOS-universal.dmg PandaGallery-macOS-universal.zip > SHA256SUMS.txt
)
echo "Release assets: $DIST_DIR"
