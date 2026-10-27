#!/usr/bin/env python3
"""Original F15 analytic motion vs recorded reference, shared widgets and encoded frames."""
import copy
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/"build/validation/derived-motion/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root/"build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    p = subprocess.run(list(map(str, args)), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=10",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out/"camera.mp4")
derived = ["Time,X,Y,Speed (m/s)"]
reference = ["Time,X,Y,Speed (m/s),Heading (deg),Longitudinal acceleration (G),Lateral acceleration (G)"]
for i in range(101):
    t = i/10
    row = f"{t},{100*(1-math.cos(t*0.2))},{100*math.sin(t*0.2)},20"
    derived.append(row)
    reference.append(row+f",{t*0.2*180/math.pi},0,{4/9.80665}")
(out/"derived.csv").write_text("\n".join(derived)+"\n")
(out/"reference.csv").write_text("\n".join(reference)+"\n")


def obj(name, kind, **kw):
    result = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=1,
                  x=5, y=10, width=25, height=70, opacity=1, visible=True, channel="", text="",
                  color="#5EE0B5", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    result.update(kw)
    return result


p = dict(formatVersion=1, name="Analytic motion comparison", width=640, height=360, fps=30,
         speedUnit="m/s", warnings=[], rangeStart=4, rangeEnd=5,
         objects=[obj("Camera", "video", inputIndex=0, x=0, y=0, width=100, height=100),
                  obj("Heading", "gauge", channel="heading", maximum=360,
                      gauge=dict(sweep=270, rotation=0, counterClockwise=False, showFace=True,
                                 showNumber=True, showLabels=True, divisions=8, decimals=0,
                                 numberingScale=1, label="Heading °", warningColor="#FF616D")),
                  obj("G force", "gforce", x=35),
                  obj("Lateral history", "graph", x=65, y=50, height=40, channel="gy", minimum=-1, maximum=1),
                  obj("Position", "map", x=65, y=5, height=40)],
         inputs=[dict(id=str(uuid.uuid4()), name=name, kind=kind, path=str(out/file), legacyIndex=i,
                      duration=10, offset=0, volume=1)
                 for i, (name, kind, file) in enumerate([("Camera", "video", "camera.mp4"), ("Data", "data", "derived.csv")])])
source = out/"derived.orrp"
source.write_text(json.dumps(p, indent=2))
ref = copy.deepcopy(p); ref["inputs"][1]["path"] = str(out/"reference.csv")
(out/"reference.orrp").write_text(json.dumps(ref, indent=2))
frames = []
for t in [4.3, 4.6]:
    pair = []
    for file, label in [(source, "derived"), (out/"reference.orrp", "reference")]:
        image = out/f"{label}-{t}.png"
        run(exe, "snapshot", file, "--time", t, "--out", image)
        pair.append(run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
    assert len(pair[0]) == len(pair[1]) == 640*360*3
    assert sum(abs(a-b) for a,b in zip(*pair))/len(pair[0]) < 0.2, "Derived widgets disagree with analytic recorded channels"
    frames.append(pair[0])
video = out/f"derived-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--out", video)
for expected, t in zip(frames, [0.3, 0.6]):
    actual = run("ffmpeg", "-v", "error", "-ss", t, "-i", video, "-frames:v", 1,
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(actual) == len(expected)
    assert sum(abs(a-b) for a,b in zip(actual,expected))/len(actual) < 3
disabled = copy.deepcopy(p)
disabled["inputs"][1]["dataSettings"] = dict(assignments={}, fields=[], headingDerivation="recordedOnly", longitudinalDerivation="recordedOnly", lateralDerivation="recordedOnly")
(out/"disabled.orrp").write_text(json.dumps(disabled, indent=2))
run(exe, "snapshot", out/"disabled.orrp", "--time", 4.3, "--out", out/"disabled.png")
actual = run("ffmpeg", "-v", "error", "-i", out/"disabled.png", "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
assert actual != frames[0], "Recorded-only modes left derived widgets active"
print("Derived motion acceptance passed: heading/G widgets agree with analytic recorded data, encoded frames match, modes disable estimates.")
print(out/"derived-4.3.png")
