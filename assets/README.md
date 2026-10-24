# App icon

`AppIcon.png` is the original generated raster master, with transparency outside the rounded tile. A mint speedometer and warm-white play button connect motorsport telemetry with video; the coral needle provides a distinct accent against the midnight-navy background.

Created with the built-in imagegen tool. This project artwork is distributed under the repository's MIT license and uses no RaceRender artwork.

`scripts/build-icon.sh` uses macOS `sips` and `iconutil` to produce `build/AppIcon.icns`, including the standard 16–1024 pixel representations. `scripts/build.sh` embeds it in the app's Resources directory and sets `CFBundleIconFile`.

## Generation prompt

```text
Use case: logo-brand. Asset type: final macOS application icon for OpenRaceRender, an open-source native telemetry video editor for motorsport. Generate one polished original icon, square 1024 by 1024 pixels. Design a dark midnight-navy rounded-square macOS icon tile with softly rounded continuous corners, centered with a modest transparent margin outside the tile. On the tile, a bold mint/turquoise speedometer arc sweeps around a crisp warm-white right-facing video play triangle; one short vivid coral needle accent points up and right from the center. The arc has only a few substantial clean ticks, not tiny numbers. Communicate speed, telemetry, and video editing through this one coherent emblem. Match a refined dark native macOS editor whose accent color is mint. Subtle dimensional enamel, gentle bevels, controlled highlights and soft depth, exceptionally clean geometry, restrained premium industrial design. Strong silhouette, balanced visual mass, excellent legibility reduced to 32 or 16 pixels. Front-on orthographic view, no perspective. The emblem occupies most of the tile with generous breathing room. No words, letters, digits, captions, watermark, scene, extra icons, decorative chart grids or checkerboard. No borrowed vendor artwork or logos. Transparency is only outside the rounded-square tile; the tile itself is opaque.
```
