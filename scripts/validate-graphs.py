#!/usr/bin/env python3
"""Original synthetic F06 graph snapshot, legacy and encoded-video acceptance."""
import copy
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/graphs/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


def display(name, kind, **settings):
    result = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=1,
                  channel="Speed", text="", color="#5EE0B5", minimum=0, maximum=100,
                  x=5, y=5, width=40, height=25, opacity=1, visible=True,
                  start=0, end=1000000, parentIndex=-1)
    result.update(settings)
    return result


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
    "color=c=0x172332:s=960x540:r=30:d=5", "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "camera.mp4")
(out / "telemetry.csv").write_text("Time,Speed,Distance,Brake\n" + "\n".join(
    f"{i/60},{50+40*math.sin(i/24)},{i*0.3},{50+50*math.cos(i/14)}" for i in range(301)))
graph = dict(axis="time", horizontalChannel="", mode="fixedBoth", timeSpan=2,
             automaticMinimum=False, automaticMaximum=False, connect=True, sortX=False,
             vertical=False, reverse=False, fill=True, background=True,
             backgroundColor="#0D1218", fillColor="#204050", lineColor="#5EE0B5", lineWidth=3,
             axes=True, numbers=True, axisColor="#546274", numberColor="#FFFFFF", axisWidth=1,
             interval=20, numberSize=20, flipSides=False, trim=True, trimColor="#546274", trimWidth=1,
             markerColor="#FFFFFF", markerSize=3, label="", labelSize=22, labelColor="#FFFFFF", referenceWidth=600)
objects = [display("Camera", "video", inputIndex=0, x=0, y=0, width=100, height=100)]
for i, (mode, axis) in enumerate([("moving", "time"), ("centered", "time"), ("fixedBoth", "time"),
                                  ("progress", "distance"), ("fixed", "channel"), ("fixedDot", "distance")]):
    g = copy.deepcopy(graph)
    g.update(mode=mode, axis=axis, label=f"{mode} / {axis}")
    if axis == "channel":
        g.update(horizontalChannel="Brake", connect=False)
    if i == 5:
        g.update(vertical=True, reverse=True)
    objects.append(display(g["label"], "graph", x=3 + (i % 2)*49, y=3+(2-i//2)*32,
                           width=46, height=29, graph=g))
p = dict(formatVersion=1, name="Graph acceptance", width=960, height=540, fps=30,
         speedUnit="mph", warnings=[], explicitDuration=5, objects=objects,
         inputs=[dict(id=str(uuid.uuid4()), name=name, path=str(out / filename), kind=kind,
                      legacyIndex=i, duration=5, offset=0, volume=1)
                 for i, (name, filename, kind) in enumerate([
                     ("Camera", "camera.mp4", "video"), ("Logger", "telemetry.csv", "data")])])
# Hold the input color pipeline constant across native/legacy comparison.
p["inputs"][0]["picture"] = dict(left=0, right=0, top=0, bottom=0, flipX=False, flipY=False,
    rotation=0, maintainAspect=True, brightness=1, contrast=1, saturation=1, sharpness=1,
    hue=0, legacyColorInterpretation=True)
source = out / "graphs.orrp"
source.write_text(json.dumps(p, indent=2))
run(exe, "convert", source, "--out", out / "graphs.rrp")
run(exe, "convert", out / "graphs.rrp", "--out", out / "reopened.orrp")
reopened = json.loads((out / "reopened.orrp").read_text())
reopened.update(width=960, height=540)
(out / "reopened.orrp").write_text(json.dumps(reopened))
for t in [0.5, 2.5, 4.5]:
    frames = []
    for name in ["graphs.orrp", "reopened.orrp"]:
        frame = out / f"{name}-{t}.png"
        run(exe, "snapshot", out / name, "--time", t, "--out", frame)
        frames.append(run("ffmpeg", "-v", "error", "-i", frame, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
    assert frames[0] == frames[1], f"Graph roundtrip changed pixels at {t}"
video_output = out / f"graphs-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--duration", 3, "--out", video_output)
metadata = json.loads(run("ffprobe", "-v", "error", "-show_streams", "-of", "json", video_output))
video = next(s for s in metadata["streams"] if s["codec_type"] == "video")
assert (video["width"], video["height"]) == (960, 540)
assert 2.9 < float(video["duration"]) < 3.1
encoded = [run("ffmpeg", "-v", "error", "-ss", t, "-i", video_output, "-frames:v", 1,
               "-f", "rawvideo", "-pix_fmt", "rgb24", "-") for t in [0.5, 2.5]]
assert len(encoded[0]) == 960*540*3
assert encoded[0] != encoded[1], "Graph export did not advance"
print("Graph acceptance passed: six plot configurations, exact RRP snapshot roundtrips, advancing encoded video.")
print(out / "graphs.orrp-2.5.png")
