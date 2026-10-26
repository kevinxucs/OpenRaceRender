#!/usr/bin/env python3
"""Original synthetic F02 author → RRP/RRT/RRO → reopen/media acceptance.

Open the generated files in RaceRender as the separate native interoperability check.
No vendor library or private session is required. Requires a release app and ffmpeg.
"""
import array
import copy
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/legacy-writer/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


def display(name, kind, **settings):
    result = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=-1,
                  channel="", text="", color="#5EE0B5", minimum=0, maximum=100,
                  x=5, y=5, width=20, height=20, opacity=1, visible=True,
                  start=0, end=1000000, parentIndex=-1)
    result.update(settings)
    return result


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x183044:s=640x360:r=30:d=3",
    "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-c:v", "libx264", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-shortest", out / "camera.mp4")
(out / "logger.csv").write_text("Time,RPM,Speed (mph)\n0,1000,0\n1,3500,30\n2,6000,60\n3,7500,80\n")
p = dict(formatVersion=1, name="Native authored compatibility", width=1280, height=720, fps=30,
         speedUnit="mph", warnings=[], notes="F02 native authoring acceptance; synthetic media and data.",
         rangeStart=0.25, rangeEnd=2.5,
         inputs=[dict(id=str(uuid.uuid4()), name="Camera", path=str(out / "camera.mp4"), kind="video",
                      legacyIndex=7, duration=3, offset=0, volume=1),
                 dict(id=str(uuid.uuid4()), name="Logger", path=str(out / "logger.csv"), kind="data",
                      legacyIndex=12, duration=3, offset=0, volume=1)],
         objects=[display("Video", "video", inputIndex=7, x=0, y=0, width=100, height=100),
                  display("RPM dial", "rpm", inputIndex=12, maximum=8000, width=30, height=53.333333),
                  display("New ellipse", "shape", x=65, y=10, width=15, height=26.666667,
                          shape=dict(kind="ellipse", fill=True, gradient=False, gradientColor="#000000",
                                     gradientAngle=90, stroke=True, strokeColor="#FFFFFF", strokeWidth=2,
                                     referenceHeight=480)),
                  display("Caption", "text", text="OPENRACERENDER / RACERENDER", x=5, y=80, width=90, height=12,
                          color="#FFFFFF", typography=dict(font="Helvetica", size=30, referenceHeight=480,
                              bold=True, italic=False, underline=False, strikethrough=False, alignment="left",
                              fitToBox=False, outline=False, outlineColor="#000000", outlineWidth=2))])

# Author entirely without legacyCommon, legacyPayload or original project bytes.
source = out / "authored.orrp"
source.write_text(json.dumps(p, indent=2))
for extension in ["rrp", "rrt"]:
    run(exe, "convert", source, "--out", out / f"authored.{extension}")
    dest = out / f"from-{extension}.orrp"
    run(exe, "convert", out / f"authored.{extension}", "--out", dest)
    decoded = json.loads(dest.read_text())
    assert [o["name"] for o in decoded["objects"]] == [o["name"] for o in p["objects"]]
    assert decoded["objects"][0]["inputIndex"] == 0
    assert decoded["objects"][1]["inputIndex"] == 1
    if extension == "rrp":
        assert decoded["rangeStart"] == 0.25 and decoded["rangeEnd"] == 2.5
    else:
        assert all(s["path"] == "" and s["duration"] == 0 for s in decoded["inputs"])

style = copy.deepcopy(p)
style["objects"] = [style["objects"][-1]]
(out / "caption.orrp").write_text(json.dumps(style))
run(exe, "convert", out / "caption.orrp", "--out", out / "caption.rro")
run(exe, "convert", out / "caption.rro", "--out", out / "from-rro.orrp")
assert json.loads((out / "from-rro.orrp").read_text())["objects"][0]["text"] == style["objects"][0]["text"]
style["objects"] = [p["objects"][1]]
(out / "gauge.orrp").write_text(json.dumps(style))
run(exe, "convert", out / "gauge.orrp", "--out", out / "gauge.rro")
print("PASS independently authored RRP, RRT and RRO; source-role remapping and marks", flush=True)

p["objects"][-1]["segments"] = [dict(id=str(uuid.uuid4()), time=1, text="SECOND SEGMENT / AUDIO MUTED")]
p["objects"][0]["segments"] = [dict(id=str(uuid.uuid4()), time=1, audio=dict(volume=0, balance=0, routing="stereo"))]
p["objects"][2]["segments"] = [dict(id=str(uuid.uuid4()), time=1, x=40)]
(out / "timeline.orrp").write_text(json.dumps(p, indent=2))
run(exe, "convert", out / "timeline.orrp", "--out", out / "timeline.rrp")
run(exe, "convert", out / "timeline.rrp", "--out", out / "from-timeline.orrp")
decoded = json.loads((out / "from-timeline.orrp").read_text())
assert decoded["objects"][-1]["segments"][0]["text"] == p["objects"][-1]["segments"][0]["text"]
video = out / "timeline.mp4"
if video.exists():
    video.unlink()
run(exe, "export", out / "timeline.rrp", "--start", 0, "--duration", 2, "--width", 640, "--out", video)
for time, active in [(0.25, True), (1.25, False)]:
    samples = array.array("f", run("ffmpeg", "-v", "error", "-ss", time, "-i", video, "-t", 0.25,
                                   "-vn", "-ac", 1, "-f", "f32le", "-"))
    rms = math.sqrt(sum(x*x for x in samples) / max(1, len(samples)))
    assert rms > 0.01 if active else rms < 0.002
    run(exe, "snapshot", out / "timeline.rrp", "--time", time, "--width", 640, "--out", out / f"frame-{time}.png")
print("PASS rebuilt RRP text/geometry/audio timeline through still and video export", flush=True)
print(f"Native RaceRender checks: {out / 'authored.rrp'}, authored.rrt, caption.rro and timeline.rrp", flush=True)
