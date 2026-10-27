#!/usr/bin/env python3
"""Original F18 analytic average/GPS/curve reference plus full-vs-chunk video checks."""
import copy
import json
import math
import subprocess
import time
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/smoothing/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=6",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "camera.mp4")
rows = ["Time,Speed (m/s)"]
reference = rows.copy()
held = rows.copy()
updates = rows.copy()
curve = ["Time,X,Y"]
for i in range(601):
    t = i/100
    rows.append(f"{t},{20+4*math.sin(10*math.pi*t)}")
    reference.append(f"{t},20")
    held.append(f"{t},{10+i//100}")
    updates.append(f"{t},{10+t}")
    u = t/3 if t <= 3 else (t-3)/3
    y = -u**3+u**2+u if t <= 3 else u**3-2*u**2+1
    curve.append(f"{t},{t/3},{y}")
for name, data in [("noise", rows), ("mean", reference), ("held", held), ("updates", updates), ("curve", curve)]:
    (out / (name+".csv")).write_text("\n".join(data)+"\n")
(out / "corners.csv").write_text("Time,X,Y\n0,0,0\n3,1,1\n6,2,0\n")


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=1,
                 x=5, y=10, width=45, height=80, opacity=1, visible=True, channel="", text="",
                 color="#5EE0B5", minimum=0, maximum=40, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


gauge = dict(sweep=270, rotation=0, counterClockwise=False, showFace=True, showNumber=True,
             showLabels=True, divisions=8, decimals=0, numberingScale=1, label="M/S", warningColor="#FF616D")
# Original complete GaugeDesign fixture (all required Codable fields).
defaults = dict(mode="needle", automaticMinimum=False, automaticMaximum=False, smoothing=0.4,
                splitAngle=135, faceColor="#121820", faceGradient=False, faceSecondColor="#000000",
                trim=True, trimColor="#FFFFFF", trimWidth=1, needleColor="#FFFFFF", centerColor="#FFFFFF",
                centerSize=5, tip=85, tail=12, needleWidth=2, taper=0, dualColor="#FFB44D", dualTip=55,
                dualTail=8, dualWidth=3, dualInterval=1000, fillInnerRadius=70, marksColor="#FFFFFF",
                minorColor="#AAAAAA", majorStyle="dash", minorStyle="dash", majorLength=10, minorLength=5,
                majorWidth=1, minorWidth=0.5, minorDivisions=4, showMajor=True, showMinor=True, pins=False,
                pinColor="#FFFFFF", pinSize=3, everyOtherNumber=False, numberExtremes=True, limitClutter=True)
caption = dict(font="Helvetica", size=12, color="#FFFFFF", bold=False, italic=False,
               automaticPosition=True, x=50, y=40)
change = dict(enabled=False, threshold=6500, color="#FF4444", gradient=False, start=6000,
              secondEnabled=False, secondThreshold=7500, secondColor="#FF0000")
for key in ["numberStyle", "labelStyle", "valueStyle"]:
    defaults[key] = dict(caption, size=30 if key == "valueStyle" else 12)
for key in ["needleChange", "markingChange", "faceChange"]:
    defaults[key] = change.copy()
gauge["design"] = defaults
p = dict(formatVersion=1, name="Smoothing comparison", width=640, height=360, fps=30,
         speedUnit="m/s", warnings=[], rangeStart=2, rangeEnd=3,
         inputs=[dict(id=str(uuid.uuid4()), name=name, kind=kind, path=str(out/file),
                      legacyIndex=i, duration=6, offset=0, volume=1)
                 for i, (name, kind, file) in enumerate([("Camera", "video", "camera.mp4"),
                      ("Engine", "data", "noise.csv"), ("Track", "data", "corners.csv"), ("GPS", "data", "held.csv")])],
         objects=[obj("Camera", "video", inputIndex=0, x=0, y=0, width=100, height=100),
                  obj("Average speed", "speed", gauge=gauge),
                  obj("Curved track", "map", inputIndex=2, x=55, y=50, width=40, height=45),
                  obj("Reconstructed GPS", "graph", inputIndex=3, x=55, y=5, width=40, height=40,
                      channel="speed", minimum=10, maximum=20)])
p["inputs"][2]["dataSettings"] = dict(assignments={}, fields=[], smoothCurves=True)
p["inputs"][3]["dataSettings"] = dict(assignments={}, fields=[], detectGPSUpdates=True)
source = out / "smoothed.orrp"
source.write_text(json.dumps(p, indent=2))
ref = copy.deepcopy(p)
ref["inputs"][1]["path"] = str(out / "mean.csv")
ref["objects"][1]["gauge"]["design"]["smoothing"] = 0
ref["inputs"][2]["path"] = str(out / "curve.csv")
ref["inputs"][2].pop("dataSettings")
ref["inputs"][3]["path"] = str(out / "updates.csv")
ref["inputs"][3].pop("dataSettings")
reference = out / "reference.orrp"
reference.write_text(json.dumps(ref, indent=2))
expected = []
for t in [2.3, 2.6]:
    frames = []
    for file, label in [(source, "smoothed"), (reference, "reference")]:
        image = out / f"{label}-{t}.png"
        run(exe, "snapshot", file, "--time", t, "--out", image)
        frames.append(run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
    assert len(frames[0]) == len(frames[1]) == 640*360*3
    error = sum(abs(a-b) for a, b in zip(*frames))/len(frames[0])
    assert error < 0.5, f"Smoothed output disagrees with analytic reference: {error}"
    expected.append(frames[0])
video = out / f"full-{uuid.uuid4().hex[:8]}.mp4"
chunk = out / f"chunk-{uuid.uuid4().hex[:8]}.mp4"
before = time.monotonic()
run(exe, "export", source, "--out", video)
elapsed = time.monotonic()-before
run(exe, "export", source, "--start", 2.3, "--duration", 0.4, "--out", chunk)
for frame, t in zip(expected, [0.3, 0.6]):
    actual = run("ffmpeg", "-v", "error", "-ss", t, "-i", video, "-frames:v", 1,
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(actual) == len(frame)
    assert sum(abs(a-b) for a, b in zip(frame, actual))/len(frame) < 3
full_frame = run("ffmpeg", "-v", "error", "-ss", 0.3, "-i", video, "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
chunk_frame = run("ffmpeg", "-v", "error", "-i", chunk, "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
assert len(full_frame) == len(chunk_frame)
assert sum(abs(a-b) for a, b in zip(full_frame, chunk_frame))/len(full_frame) < 2
print(f"Smoothing acceptance passed: analytic average, held GPS and curved map agree; encoded frames and nonzero chunk agree. 1 s @ 640×360 encoded in {elapsed:.3f} s (local check only).")
print(out / "smoothed-2.3.png")
