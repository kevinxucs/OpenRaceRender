#!/usr/bin/env python3
"""Compare matched video chunks locally. Requires ffmpeg/ffprobe; no Python packages.

Example: compare-renders.py reference.mp4 candidate.mp4 --out build/comparison
For an untagged Rec.709 reference: --reference-matrix bt709
ROI coordinates refer to the scaled snapshots: --roi sky:240:40:710:190
"""
import argparse
import html
import json
import math
from pathlib import Path
import re
import subprocess


def run(*args):
    return subprocess.run(list(map(str, args)), check=True, capture_output=True)


def probe(path):
    return json.loads(run("ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path).stdout)


def metrics(a, b, width, roi):
    x, y, w, h = roi
    absolute = squared = count = 0
    for row in range(y, y + h):
        lo, hi = (row * width + x) * 3, (row * width + x + w) * 3
        for first, second in zip(a[lo:hi], b[lo:hi]):
            delta = first - second
            absolute += abs(delta)
            squared += delta * delta
            count += 1
    return dict(mae=absolute / count, psnr_db=10 * math.log10(255 * 255 * count / squared) if squared else None)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--times", default="0,2,4")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--reference-matrix", choices=["auto", "bt709", "bt601"], default="auto")
    parser.add_argument("--roi", action="append", default=[], metavar="NAME:X:Y:WIDTH:HEIGHT")
    args = parser.parse_args()
    references, candidates = probe(args.reference), probe(args.candidate)
    rv = next(s for s in references["streams"] if s["codec_type"] == "video")
    cv = next(s for s in candidates["streams"] if s["codec_type"] == "video")
    if (rv["width"], rv["height"]) != (cv["width"], cv["height"]):
        parser.error("Use matching output dimensions before comparing rendering quality.")
    times = [float(t) for t in args.times.split(",")]
    duration = min(float(p["format"]["duration"]) for p in [references, candidates])
    if not times or any(not math.isfinite(t) or t < 0 or t >= duration for t in times):
        parser.error("Snapshot times must lie inside both videos.")
    if args.width < 2 or args.width > 7680:
        parser.error("Snapshot width must be 2–7680.")
    width = args.width
    height = round(width * rv["height"] / rv["width"] / 2) * 2
    rois = {"full": (0, 0, width, height)}
    for spec in args.roi:
        name, *coordinates = spec.split(":")
        if len(coordinates) != 4:
            parser.error("Each ROI needs NAME:X:Y:WIDTH:HEIGHT.")
        x, y, w, h = map(int, coordinates)
        if min(x, y) < 0 or min(w, h) <= 0 or x + w > width or y + h > height:
            parser.error("ROI lies outside the snapshot.")
        rois[name] = (x, y, w, h)
    if args.out.exists() and any(args.out.iterdir()):
        parser.error("Choose an empty output directory.")
    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    frames = []
    for index, time in enumerate(times):
        files = []
        pixels = []
        for label, source in [("reference", args.reference), ("candidate", args.candidate)]:
            path = args.out / f"{index}-{label}.png"
            scaling = f"scale={width}:{height}:flags=lanczos"
            if label == "reference" and args.reference_matrix != "auto":
                scaling += f":in_color_matrix={args.reference_matrix}"
            run("ffmpeg", "-v", "error", "-ss", time, "-i", source, "-frames:v", "1", "-vf", scaling, path)
            files.append(path)
            pixels.append(run("ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-").stdout)
        entry = dict(time=time, regions={name: metrics(*pixels, width, roi) for name, roi in rois.items()})
        log = run("ffmpeg", "-v", "info", "-i", files[0], "-i", files[1], "-filter_complex", "[0:v]format=gbrp[a];[1:v]format=gbrp[b];[a][b]ssim", "-f", "null", "-").stderr.decode()
        entry["ssim"] = float(re.search(r"All:([\d.]+)", log).group(1))
        run("ffmpeg", "-v", "error", "-i", files[0], "-i", files[1], "-filter_complex", "hstack", "-frames:v", "1", args.out / f"{index}-side-by-side.png")
        run("ffmpeg", "-v", "error", "-i", files[0], "-i", files[1], "-filter_complex", "blend=all_mode=difference,lutrgb=r=val*4:g=val*4:b=val*4", "-frames:v", "1", args.out / f"{index}-difference.png")
        frames.append(entry)
        details = " · ".join(f"{html.escape(name)} MAE {v['mae']:.2f}" for name, v in entry["regions"].items())
        rows.append(f'''<section><h2>{time:.3f} s</h2><p>RGB SSIM {entry['ssim']:.5f} · {details}</p>
<div class="wipe"><img src="{index}-reference.png"><img class="candidate" src="{index}-candidate.png"></div>
<input aria-label="Compare reference and candidate at {time} seconds" type="range" value="50" oninput="this.previousElementSibling.lastElementChild.style.clipPath='inset(0 0 0 '+this.value+'%)'">
<details><summary>Difference ×4</summary><img src="{index}-difference.png"></details></section>''')
    report = dict(reference=args.reference.name, candidate=args.candidate.name, reference_matrix=args.reference_matrix,
        dimensions=[width, height], reference_streams=references["streams"], candidate_streams=candidates["streams"], frames=frames)
    (args.out / "metrics.json").write_text(json.dumps(report, indent=2))
    (args.out / "index.html").write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Render comparison</title><style>body{background:#15191f;color:#e8eef5;font:16px system-ui;max-width:1280px;margin:32px auto;padding:16px}img{width:100%;display:block}section{margin:32px 0}.wipe{position:relative}.candidate{position:absolute;inset:0;clip-path:inset(0 0 0 50%)}input{width:100%}summary{cursor:pointer;padding:12px 0}p{color:#b9c9db}</style>
<h1>Render comparison</h1><p>Left: reference. Right: OpenRaceRender. Drag to compare the same pixels. Differences include layout, history, font rasterization and compression; SSIM alone does not establish visual parity.</p>''' + "".join(rows) + "</html>")
    print(args.out / "index.html")


if __name__ == "__main__":
    main()
