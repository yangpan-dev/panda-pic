#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/module-cache"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
TEST_OPTIONS=(--disable-xctest --build-system native --disable-sandbox --cache-path "$PROJECT_ROOT/.build/cache" --config-path "$PROJECT_ROOT/.build/config" --security-path "$PROJECT_ROOT/.build/security")
for FRAMEWORK_PATH in "$DEVELOPER_DIR_PATH/Library/Developer/Frameworks" "$DEVELOPER_DIR_PATH/Library/Frameworks" "$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks"; do
  if [[ -d "$FRAMEWORK_PATH/Testing.framework" ]]; then
    TEST_OPTIONS+=(-Xswiftc -F -Xswiftc "$FRAMEWORK_PATH" -Xlinker -F -Xlinker "$FRAMEWORK_PATH" -Xlinker -rpath -Xlinker "$FRAMEWORK_PATH")
    break
  fi
done
swift test "${TEST_OPTIONS[@]}"
