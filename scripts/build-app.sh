#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION="${1:-release}"
TARGET_ARCH="${2:-native}"
OUTPUT_ROOT="${3:-$PROJECT_ROOT/output}"
if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
  echo "Usage: scripts/build-app.sh [release|debug] [native|arm64|x86_64|universal] [output-directory]" >&2
  exit 1
fi
if [[ "$TARGET_ARCH" != "native" && "$TARGET_ARCH" != "arm64" && "$TARGET_ARCH" != "x86_64" && "$TARGET_ARCH" != "universal" ]]; then
  echo "Unknown architecture: $TARGET_ARCH" >&2
  exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/module-cache"
SWIFT_OPTIONS=(--build-system native --disable-sandbox --cache-path "$PROJECT_ROOT/.build/cache" --config-path "$PROJECT_ROOT/.build/config" --security-path "$PROJECT_ROOT/.build/security")
if [[ "$TARGET_ARCH" == "universal" ]]; then
  ARCH_BINARIES=()
  for BUILD_ARCH in arm64 x86_64; do
    swift build -c "$CONFIGURATION" --triple "$BUILD_ARCH-apple-macosx14.0" "${SWIFT_OPTIONS[@]}"
    BIN_DIR="$(swift build -c "$CONFIGURATION" --triple "$BUILD_ARCH-apple-macosx14.0" --show-bin-path "${SWIFT_OPTIONS[@]}")"
    ARCH_BINARIES+=("$BIN_DIR/PandaGallery")
  done
  mkdir -p "$PROJECT_ROOT/.build/distribution"
  APP_BINARY="$PROJECT_ROOT/.build/distribution/PandaGallery-universal"
  lipo -create "${ARCH_BINARIES[@]}" -output "$APP_BINARY"
  lipo "$APP_BINARY" -verify_arch arm64
  lipo "$APP_BINARY" -verify_arch x86_64
else
  if [[ "$TARGET_ARCH" != "native" ]]; then
    SWIFT_OPTIONS+=(--triple "$TARGET_ARCH-apple-macosx14.0")
  fi
  swift build -c "$CONFIGURATION" "${SWIFT_OPTIONS[@]}"
  BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path "${SWIFT_OPTIONS[@]}")"
  APP_BINARY="$BIN_DIR/PandaGallery"
fi
APP_PATH="$OUTPUT_ROOT/熊猫图库.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$APP_BINARY" "$APP_PATH/Contents/MacOS/PandaGallery"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/PandaGallery.png" "$APP_PATH/Contents/Resources/PandaGallery.png"
cp -R "$PROJECT_ROOT/Resources/Samples" "$APP_PATH/Contents/Resources/"
cp "$PROJECT_ROOT/Resources/PhotoCredits.md" "$APP_PATH/Contents/Resources/PhotoCredits.md"
cp "$PROJECT_ROOT/Resources/IconPrompt.txt" "$APP_PATH/Contents/Resources/IconPrompt.txt"
ICONSET="$PROJECT_ROOT/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for ICON_SIZE in 16 32 128 256 512; do
  sips -z "$ICON_SIZE" "$ICON_SIZE" "$PROJECT_ROOT/Resources/PandaGallery.png" --out "$ICONSET/icon_${ICON_SIZE}x${ICON_SIZE}.png" >/dev/null
  RETINA_SIZE=$((ICON_SIZE * 2))
  sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$PROJECT_ROOT/Resources/PandaGallery.png" --out "$ICONSET/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$PROJECT_ROOT/Resources/AppIcon.icns"
# A local ad-hoc signature enables normal launch. Developer ID signing is a separate distribution step.
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --all-architectures --deep --strict "$APP_PATH"
echo "$APP_PATH"
