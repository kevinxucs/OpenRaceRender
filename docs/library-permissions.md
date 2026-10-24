# Library storage and macOS permissions

OpenRaceRender stores its managed library at:

```text
~/Library/Application Support/OpenRaceRender/Library/
  Templates/
  Styles/
  Images/
  Video Positions/
```

The library browser searches this location and packaged app resources. It never probes `~/Documents/OpenRaceRender` or `~/Documents/RaceRender 3` automatically, including when an old library might need migration. Template and style saves default to the managed library. **Open library folder** reveals it in Finder.

## Why the prompts occurred

Older builds automatically enumerated both Documents libraries when the library browser appeared and saved custom layouts there by default. This made library discovery depend on macOS protected-folder access. Apple identifies Library/Application Support as the appropriate location for app-managed templates and resources: [File System Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html).

Local builds also use ad-hoc code signing by default. Inspection of the affected app showed a designated requirement containing its exact code-directory hash. Rebuilding changes that identity, which can cause old macOS privacy grants to stop matching. Apple's Developer Technical Support confirms that ad-hoc signing lacks a stable identity and can cause TCC issues: [Apple Developer Forums](https://developer.apple.com/forums/thread/751658), [TN3127: Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Moving managed resources removes the need to access Documents during normal launch and library browsing. Explicitly opening a project or media file in a protected folder may still require that folder's normal macOS authorization.

## Import an old library once

In **Templates → Import library…**, select the old RaceRender or OpenRaceRender library folder, or a single category folder. The app copies its files into Application Support, preserves subfolders and original files, and keeps any destination file that already exists. Repeating import is safe. Hidden files are excluded; symbolic links are rejected.

Alternatively, after building the app:

```sh
./build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender import-library "$HOME/Documents/RaceRender 3"
./build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender import-library "$HOME/Documents/OpenRaceRender"
```

Import only folders that exist. Vendor assets keep their original licenses. They remain local and are not included in the public source repository. **Choose folder…** remains available for browsing another folder explicitly without copying it.

To package the imported library in a portable local app:

```sh
./scripts/build.sh --library "$HOME/Library/Application Support/OpenRaceRender/Library"
```

## Stable signing for development

When an existing Apple Development or Developer ID signing identity is available in your keychain, the build can use it:

```sh
./scripts/build.sh --sign-identity 'Apple Development: Your Name (TEAMID)'
# Or configure subsequent builds:
export OPENRACERENDER_SIGN_IDENTITY='Apple Development: Your Name (TEAMID)'
```

This selects an existing certificate; the build creates no keys or certificates and changes no macOS privacy settings. Default and CI builds still work with ad-hoc signing. The resource-location fix does not depend on a signing certificate.

## Regression coverage

Tests verify that default roots exclude old Documents libraries even when populated, Application Support customizations override bundled files, and explicit import preserves bytes/subfolders, leaves originals unchanged, keeps existing customizations, and is repeatable. The local migration copied and checked 365 files: 62 templates, 255 styles, 28 image styles and 20 video-position presets.

Hands-on verification on 2026-10-24 launched the rebuilt app twice and opened Templates/Styles without a Documents prompt. The migrated custom dashboard appeared after relaunch, and a repeat UI import preserved all 62 existing templates. All 365 migrated layouts read successfully (1,093 display objects).
