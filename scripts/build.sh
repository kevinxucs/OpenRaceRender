#!/bin/zsh
set -eu
library_source=''
while (( $# )); do
  case "$1" in
    --library)
      if (( $# < 2 )) || [[ ! -d "$2" ]]; then
        print -u2 'Specify --library with an existing library directory.'
        exit 1
      fi
      library_source="${2:A}"
      shift 2
      ;;
    --help|-h)
      print 'Usage: ./scripts/build.sh [--library "/path/to/RaceRender 3"]'
      print 'The optional library is copied into this local app build. Default builds contain no vendor assets.'
      exit 0
      ;;
    *) print -u2 "Unknown build option: $1"; exit 1 ;;
  esac
done
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -debug-info-format none -c release
mkdir -p build
staging_directory=$(mktemp -d "$PWD/build/.app-bundle.XXXXXX")
trap 'rm -rf "$staging_directory"' EXIT
app_bundle="$staging_directory/OpenRaceRender.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp .build/release/OpenRaceRender "$app_bundle/Contents/MacOS/OpenRaceRender"
cp scripts/Info.plist "$app_bundle/Contents/Info.plist"
if [[ -n "$library_source" ]]; then
  python3 scripts/bundle-library.py "$library_source" "$app_bundle/Contents/Resources/RaceRender 3"
fi
codesign --force --sign - "$app_bundle"
rm -rf build/OpenRaceRender.app
mv "$app_bundle" build/OpenRaceRender.app
print 'Built build/OpenRaceRender.app'
