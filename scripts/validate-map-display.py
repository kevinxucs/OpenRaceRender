#!/usr/bin/env python3
"""F21: exact zoom/rotation/follow marker positions and shared artwork transform."""
import base64
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/map-display/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


# Generate/validate the original circular-course fixture first.
run("python3", root / "scripts/validate-map-comparison.py")
p = json.loads((root / "build/validation/map-comparison/acceptance/lapGhost.orrp").read_text())
run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=black:s=640x360,drawbox=x=315:y=97:w=11:h=11:color=magenta:t=fill",
    "-frames:v", 1, out / "background.png")
p["objects"][1]["artwork"] = base64.b64encode((out / "background.png").read_bytes()).decode()
style = dict(trace="all", drawCourse=True, drawPosition=True, drawStart=False, icon="dot", markerSize=5.6,
             zoom=1.5, rotation=90, headingUp=False, followPosition=False, resolution="high",
             lineColor="#E4EAF1", edgeColor="#111821", lineWidth=1.2, edgeWidth=2.3, alignBackground=True)
p["objects"][1]["mapSettings"] = style


def centroid(frame, color):
    points = []
    for i in range(0, len(frame), 3):
        if all(abs(frame[i+k]-color[k]) <= 8 for k in range(3)):
            points.append(((i//3) % 640, (i//3)//640))
    assert len(points) > 30, f"Missing map/artwork color {color}"
    return sum(x for x, _ in points)/len(points), sum(y for _, y in points)/len(points)


frames = {}
for name, aligned, follow in [("aligned", True, False), ("fixed-artwork", False, False), ("follow", True, True)]:
    style["alignBackground"] = aligned
    style["followPosition"] = follow
    source = out / f"{name}.orrp"
    source.write_text(json.dumps(p, indent=2))
    image = out / f"{name}.png"
    run(exe, "snapshot", source, "--time", 20, "--out", image)
    frame = run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    frames[name] = frame
    green = centroid(frame, (94, 224, 181))
    # Primary is at 60° on a 50 m circle. Apply 1.5× and 90° clockwise about the map center.
    expected = (320, 180) if follow else (320+50*math.sin(math.pi/3)*3.096*1.5, 180+50*math.cos(math.pi/3)*3.096*1.5)
    assert math.dist(green, expected) < 2, (name, green, expected)
    if not follow:
        magenta = centroid(frame, (255, 0, 255))
        expected = (437, 180) if aligned else (320, 102)
        assert math.dist(magenta, expected) < 2, (name, magenta, expected)
video = out / f"aligned-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", out / "aligned.orrp", "--out", video)
encoded = run("ffmpeg", "-v", "error", "-i", video, "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
assert len(encoded) == len(frames["aligned"])
assert sum(abs(a-b) for a, b in zip(encoded, frames["aligned"]))/len(encoded) < 3
print("Map-display acceptance passed: rotated/zoomed/follow markers match coordinate math; artwork follows the same transform or stays fixed as selected; encoded frames match.")
print(out / "aligned.png")
