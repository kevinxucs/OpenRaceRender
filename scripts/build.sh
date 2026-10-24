#!/bin/zsh
set -eu
library_source=''
signing_identity="${OPENRACERENDER_SIGN_IDENTITY:--}"
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
    --sign-identity)
      if (( $# < 2 )) || [[ -z "$2" ]]; then
        print -u2 'Specify --sign-identity with an existing signing identity name or SHA-1.'
        exit 1
      fi
      signing_identity="$2"
      shift 2
      ;;
    --help|-h)
      print 'Usage: ./scripts/build.sh [--library "/path/to/library"] [--sign-identity "NAME or SHA-1"]'
      print 'The optional library is copied into this local app build. Default builds contain no vendor assets.'
      print 'Signing defaults to ad hoc. OPENRACERENDER_SIGN_IDENTITY can select an existing certificate.'
      exit 0
      ;;
    *) print -u2 "Unknown build option: $1"; exit 1 ;;
  esac
done
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -debug-info-format none -c release
./scripts/build-icon.sh
mkdir -p build
staging_directory=$(mktemp -d "$PWD/build/.app-bundle.XXXXXX")
trap 'rm -rf "$staging_directory"' EXIT
app_bundle="$staging_directory/OpenRaceRender.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp .build/release/OpenRaceRender "$app_bundle/Contents/MacOS/OpenRaceRender"
cp scripts/Info.plist "$app_bundle/Contents/Info.plist"
cp build/AppIcon.icns "$app_bundle/Contents/Resources/AppIcon.icns"
if [[ -n "$library_source" ]]; then
  python3 scripts/bundle-library.py "$library_source" "$app_bundle/Contents/Resources/RaceRender 3"
fi
codesign --force --sign "$signing_identity" "$app_bundle"
rm -rf build/OpenRaceRender.app
mv "$app_bundle" build/OpenRaceRender.app
print 'Built build/OpenRaceRender.app'
