#!/usr/bin/env python3
"""F19 GPS crossing modes/ignored trigger vs independent recorded lap boundaries."""
import copy
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/finish-line/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=27",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "camera.mp4")
points = []
for lap in range(3):
    for t, x, y in [(0, 0, -10), (1, 0, 30), (2, 100, 30), (4, 100, -10), (6, 0, -10)]:
        points.append((lap*10+t, x, y))


def position(t):
    for a, b in zip(points, points[1:]):
        if a[0] <= t <= b[0]:
            u = (t-a[0])/(b[0]-a[0])
            return a[1]+(b[1]-a[1])*u, a[2]+(b[2]-a[2])*u
    return points[-1][1:]


def csv(times, boundaries=None):
    rows = ["Time,Latitude,Longitude"+(",Lap" if boundaries else "")]
    for t in sorted(set(times)):
        x, y = position(t)
        row = f"{t},{36+y/111195},{-121+x/(111195*math.cos(math.radians(36)))}"
        if boundaries:
            row += ","+str(sum(t >= b for b in boundaries))
        rows.append(row)
    return "\n".join(rows)+"\n"


(out / "gps.csv").write_text(csv([p[0] for p in points]))


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=1,
                 x=5, y=10, width=28, height=35, opacity=1, visible=True, channel="", text="",
                 color="#5EE0B5", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


p = dict(formatVersion=1, name="GPS finish comparison", width=640, height=360, fps=30,
         speedUnit="m/s", warnings=[], rangeStart=10, rangeEnd=12,
         inputs=[dict(id=str(uuid.uuid4()), name=name, kind=kind, path=str(out/file),
                      legacyIndex=i, duration=26 if kind == "data" else 27, offset=0, volume=1)
                 for i, (name, kind, file) in enumerate([("Camera", "video", "camera.mp4"), ("GPS", "data", "gps.csv")])],
         objects=[obj("Camera", "video", inputIndex=0, x=0, y=0, width=100, height=100),
                  obj("Lap", "lap", y=55), obj("Lap timer", "timer"),
                  obj("Best lap", "bestTime", x=37, y=55),
                  obj("Track", "map", x=68, y=10, height=80)])
for mode, crossing in [("interpolated", 0.25), ("sample", 1)]:
    settings = dict(assignments={}, fields=[], ignoreLapTriggers=1,
                    finishLine=dict(latitude=36, longitude=-121, heading=0, width=40,
                                    minimumLap=8, headingTolerance=60, eastTolerance=10, precision=mode))
    p["inputs"][1]["dataSettings"] = settings
    source = out / f"{mode}.orrp"
    source.write_text(json.dumps(p, indent=2))
    boundaries = [crossing+10*i for i in range(3)]
    ref_file = out / f"{mode}-reference.csv"
    ref_file.write_text(csv([p[0] for p in points]+boundaries, boundaries))
    ref = copy.deepcopy(p)
    ref["inputs"][1]["path"] = str(ref_file)
    ref["inputs"][1]["dataSettings"] = dict(assignments=dict(lap="Lap"), fields=[], ignoreLapTriggers=1)
    reference = out / f"{mode}-reference.orrp"
    reference.write_text(json.dumps(ref, indent=2))
    expected = []
    for t in [10.4, 11.3]:
        frames = []
        for file, label in [(source, mode), (reference, mode+"-reference")]:
            image = out / f"{label}-{t}.png"
            run(exe, "snapshot", file, "--time", t, "--out", image)
            frames.append(run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
        assert len(frames[0]) == len(frames[1]) == 640*360*3
        error = sum(abs(a-b) for a, b in zip(*frames))/len(frames[0])
        assert error < 0.2, f"{mode} disagrees with exact recorded lap boundaries: {error}"
        expected.append(frames[0])
    video = out / f"{mode}-{uuid.uuid4().hex[:8]}.mp4"
    run(exe, "export", source, "--out", video)
    for frame, t in zip(expected, [0.4, 1.3]):
        actual = run("ffmpeg", "-v", "error", "-ss", t, "-i", video, "-frames:v", 1,
                     "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
        assert len(actual) == len(frame)
        assert sum(abs(a-b) for a, b in zip(frame, actual))/len(frame) < 3
print("Finish-line acceptance passed: interpolated/sample crossings and ignored warmup trigger match exact recorded lap boundaries in snapshots and encoded frames.")
print(out / "interpolated-11.3.png")
