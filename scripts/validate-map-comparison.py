#!/usr/bin/env python3
"""Original F20 circular runs: independently calculated marker pixels and encoded chunk consistency."""
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/map-comparison/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


def position(t):
    elapsed, duration = (t, 10) if t < 10 else (t-10, 8) if t < 18 else (t-18, 12)
    theta = elapsed/duration*2*math.pi
    return 50*math.cos(theta), 50*math.sin(theta)


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=31",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "camera.mp4")
rows = ["Time,Latitude,Longitude,Lap"]
for i in range(3001):
    t = i/100
    x, y = position(t)
    rows.append(f"{t},{36+y/111195},{-121+x/(111195*math.cos(math.radians(36)))},{1 if t < 10 else 2 if t < 18 else 3}")
(out / "runs.csv").write_text("\n".join(rows)+"\n")


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=1,
                 x=0, y=0, width=100, height=100, opacity=1, visible=True, channel="", text="",
                 color="#5EE0B5", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


inputs = [dict(id=str(uuid.uuid4()), name=name, kind=kind, path=str(out/file),
               legacyIndex=i, duration=30 if kind == "data" else 31, offset=0, volume=1)
          for i, (name, kind, file) in enumerate([("Camera", "video", "camera.mp4"), ("Primary", "data", "runs.csv"), ("Reference", "data", "runs.csv")])]
for source in inputs[1:]:
    source["dataSettings"] = dict(assignments=dict(lap="Lap"), fields=[])
inputs[2]["offset"] = -10
comparison = dict(referenceInputIndex=2, mode="timeline", primaryLapStart=18,
                  showReferenceTrace=False, referenceColor="#FFB44D", showLabels=False)
p = dict(formatVersion=1, name="Circular run comparison", width=640, height=360, fps=30,
         speedUnit="m/s", warnings=[], explicitDuration=31, rangeStart=20, rangeEnd=21,
         inputs=inputs, objects=[obj("Camera", "video", inputIndex=0), obj("Comparison", "map", mapComparison=comparison)])


def centroid(frame, color):
    points = []
    for index in range(0, len(frame), 3):
        if all(abs(frame[index+k]-color[k]) <= 3 for k in range(3)):
            pixel = index//3
            points.append((pixel % 640, pixel//640))
    assert len(points) > 50, f"Missing comparison marker: {color}"
    return sum(x for x, _ in points)/len(points), sum(y for _, y in points)/len(points)


for mode in ["timeline", "lapGhost"]:
    p["objects"][1]["mapComparison"]["mode"] = mode
    source = out / f"{mode}.orrp"
    source.write_text(json.dumps(p, indent=2))
    expected = []
    for t in [20, 20.4]:
        image = out / f"{mode}-{t}.png"
        run(exe, "snapshot", source, "--time", t, "--out", image)
        frame = run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
        assert len(frame) == 640*360*3
        # Shared bounds are a 100 m square, scaled by 86% of the 360 px plot height.
        for clock, color in [(t, (94, 224, 181)), (t-10 if mode == "timeline" else 10+t-18, (255, 180, 77))]:
            x, y = position(clock)
            expected_x, expected_y = 320+x*3.096, 180-y*3.096
            actual_x, actual_y = centroid(frame, color)
            assert math.hypot(actual_x-expected_x, actual_y-expected_y) < 2, (mode, clock, (actual_x, actual_y), (expected_x, expected_y))
        expected.append(frame)
    video = out / f"{mode}-{uuid.uuid4().hex[:8]}.mp4"
    chunk = out / f"{mode}-chunk-{uuid.uuid4().hex[:8]}.mp4"
    run(exe, "export", source, "--out", video)
    run(exe, "export", source, "--start", 20.4, "--duration", 0.3, "--out", chunk)
    full = run("ffmpeg", "-v", "error", "-ss", 0.4, "-i", video, "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    part = run("ffmpeg", "-v", "error", "-i", chunk, "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(full) == len(part) == len(expected[1])
    assert sum(abs(a-b) for a, b in zip(full, expected[1]))/len(full) < 3
    assert sum(abs(a-b) for a, b in zip(full, part))/len(full) < 2
print("Map-comparison acceptance passed: timeline and lap-ghost marker pixels match independently calculated positions; encoded snapshots and nonzero chunks agree.")
print(out / "lapGhost-20.png")
