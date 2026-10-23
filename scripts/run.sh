#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if [[ ! -x .build/release/OpenRaceRender ]]; then ./scripts/build.sh; fi
exec .build/release/OpenRaceRender "$@"
