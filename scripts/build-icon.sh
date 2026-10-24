#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build
icon_directory=$(mktemp -d "$PWD/build/.app-icon.XXXXXX")
trap 'rm -rf "$icon_directory"' EXIT
icon_set="$icon_directory/AppIcon.iconset"
mkdir -p "$icon_set"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/AppIcon.png --out "$icon_set/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" assets/AppIcon.png --out "$icon_set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_set" -o build/AppIcon.icns
