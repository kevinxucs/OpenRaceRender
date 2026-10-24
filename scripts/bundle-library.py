#!/usr/bin/env python3
"""Copy a locally supplied layout library into an app's Resources directory."""

import hashlib
import json
from pathlib import Path
import shutil
import sys


def bundle(source, destination):
    source = source.expanduser().resolve(strict=True)
    destination = destination.resolve()
    if not source.is_dir():
        raise ValueError("Library source must be a directory.")
    if destination == source or source in destination.parents:
        raise ValueError("Destination must be outside the source library.")
    if destination.exists():
        raise ValueError("Destination already exists; use a fresh app bundle.")
    folders = ("Templates", "Styles", "Images", "Video Positions")
    files = []
    for name in folders:
        folder = source / name
        if not folder.exists():
            continue
        if folder.is_symlink() or not folder.is_dir():
            raise ValueError(f"Expected an ordinary directory: {folder}")
        for path in sorted(folder.rglob("*")):
            relative = path.relative_to(source)
            if any(part.startswith(".") for part in relative.parts):
                continue
            if path.is_symlink():
                raise ValueError(f"Library symlinks are not supported: {relative}")
            if path.is_dir():
                continue
            if not path.is_file():
                raise ValueError(f"Expected an ordinary file: {relative}")
            files.append((path, relative))
    if not any(path.suffix.lower() in (".rrt", ".rro", ".orrt") for path, _ in files):
        raise ValueError("No layouts found in Templates, Styles, Images or Video Positions.")
    destination.mkdir(parents=True)
    manifest = []
    for path, relative in files:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        target.chmod(0o644)
        manifest.append({"path": relative.as_posix(), "bytes": target.stat().st_size,
                         "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
    data = {"formatVersion": 1, "files": manifest,
            "notice": "Locally supplied third-party files retain their original licenses; "
                      "they are not covered by OpenRaceRender's MIT license."}
    (destination / "library-manifest.json").write_text(json.dumps(data, indent=2) + "\n")
    print(f"Bundled {len(manifest)} library files ({sum(f['bytes'] for f in manifest):,} bytes).")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: bundle-library.py SOURCE_DIRECTORY DESTINATION_DIRECTORY")
    try:
        bundle(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError) as error:
        sys.exit(f"Cannot bundle library: {error}")
