#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -debug-info-format none -c release
mkdir -p 'build/OpenRaceRender.app/Contents/MacOS'
cp .build/release/OpenRaceRender 'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'
cp scripts/Info.plist 'build/OpenRaceRender.app/Contents/Info.plist'
codesign --force --sign - 'build/OpenRaceRender.app'
