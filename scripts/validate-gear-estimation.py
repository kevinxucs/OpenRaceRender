#!/usr/bin/env python3
"""Original F16 learned vs known manual ratios, slip/unknown, styles and encoded chunks."""
import copy
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/"build/validation/gear-estimation/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root/"build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    p = subprocess.run(list(map(str, args)), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=10",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out/"camera.mp4")
rows = ["Time,Speed (m/s),RPM"]
for i in range(201):
    t = i/20
    if t < 0.5:
        speed, rpm = 0, 1100
    else:
        ratio = 200 if t < 3 else 140 if t < 6 else 100
        if 4.4 <= t <= 4.6:
            ratio = 175  # Brief clutch/slip-like mismatch, not another gear.
        speed = 12+0.1*t
        rpm = speed*ratio*(1+0.006*math.sin(t*2))
    rows.append(f"{t},{speed},{rpm}")
(out/"engine.csv").write_text("\n".join(rows)+"\n")


def obj(name, kind, **kw):
    result = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=1,
                  x=10, y=20, width=20, height=60, opacity=1, visible=True, channel="", text="",
                  color="#5EE0B5", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    result.update(kw)
    return result


hud = dict(role="gear", label="GEAR", unit="", decimals=0, multiplier=1)
gt = dict(hud, presentation="gt")
p = dict(formatVersion=1, name="Gear estimation acceptance", width=640, height=360, fps=30,
         speedUnit="mph", warnings=[], objects=[
             obj("Camera", "video", inputIndex=0, x=0, y=0, width=100, height=100),
             obj("Native gear", "gear"), obj("Apex gear", "gear", x=40, hud=hud),
             obj("GT gear", "gear", x=70, hud=gt)],
         inputs=[dict(id=str(uuid.uuid4()), name=name, kind=kind, path=str(out/file), legacyIndex=i,
                      duration=10, offset=0, volume=1)
                 for i, (name, kind, file) in enumerate([("Camera", "video", "camera.mp4"), ("Engine", "data", "engine.csv")])])
source = out/"automatic.orrp"
source.write_text(json.dumps(p, indent=2))
manual = copy.deepcopy(p)
manual["inputs"][1]["dataSettings"] = dict(assignments={}, fields=[], gearDerivation="calculate", gearEstimation=dict(ratios=[200,140,100]))
(out/"manual.orrp").write_text(json.dumps(manual, indent=2))
frames = {}
for t in [0.1, 1.0, 3.5, 4.5, 7.0]:
    pair = []
    for project, label in [(source, "automatic"), (out/"manual.orrp", "manual")]:
        image = out/f"{label}-{t}.png"
        run(exe, "snapshot", project, "--time", t, "--out", image)
        pair.append(run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
    assert pair[0] == pair[1], "Learned gears disagree with the independent known-ratio calibration"
    frames[t] = pair[0]
assert frames[0.1] == frames[4.5], "Stopped and unmatched samples should both show unknown, never neutral"
assert len({frames[t] for t in [1.0, 3.5, 7.0]}) == 3, "Gear changes did not advance"
# Chunk starts after first gear, but calibration still uses the whole source.
video = out/f"gear-chunk-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--start", 3, "--duration", 2, "--out", video)
for session, offset in [(3.5, 0.5), (4.5, 1.5)]:
    actual = run("ffmpeg", "-v", "error", "-ss", offset, "-i", video, "-frames:v", 1,
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    expected = frames[session]
    assert len(actual) == len(expected)
    assert sum(abs(a-b) for a,b in zip(actual,expected))/len(actual) < 3
print("Gear acceptance passed: learned/manual gears, unknown slip/stopped samples, three built-in styles and unchanged chunk calibration.")
print(out/"automatic-3.5.png")
