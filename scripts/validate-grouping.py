#!/usr/bin/env python3
"""Original synthetic F03 group visibility, camera/audio export and legacy roundtrip acceptance."""
import array
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/grouping/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    p = subprocess.run(list(map(str, args)), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


def display(name, kind, **settings):
    o = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=-1,
             channel="", text="", color="#5EE0B5", minimum=0, maximum=100,
             x=5, y=5, width=20, height=20, opacity=1, visible=True,
             start=0, end=1000000, parentIndex=-1)
    o.update(settings)
    return o


def segment(time, **settings):
    return dict(id=str(uuid.uuid4()), time=time, **settings)


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x204080:s=320x180:r=30:d=3",
    "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-c:v", "libx264", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-shortest", out / "camera.mp4")
group = display("Camera and overlay group", "group", x=0, y=0, width=100, height=100,
                segments=[segment(1, visible=False), segment(2, visible=True, x=20, width=60)])
video = display("Camera", "video", inputIndex=7, parentID=group["id"], x=0, y=0, width=100, height=100,
                picture=dict(left=0, right=0, top=0, bottom=0, flipX=False, flipY=False, rotation=0,
                             maintainAspect=False, brightness=1, contrast=1, saturation=1),
                segments=[segment(2, x=20, width=60)])
shape = display("Grouped rectangle", "shape", parentID=group["id"], x=10, y=10, width=20, height=20,
                color="#FF0000", shape=dict(kind="rectangle", fill=True, gradient=False,
                    gradientColor="#000000", gradientAngle=90, stroke=False,
                    strokeColor="#FFFFFF", strokeWidth=1, referenceHeight=480),
                segments=[segment(2, x=26, width=12)])
p = dict(formatVersion=1, name="Grouping acceptance", width=320, height=180, fps=30,
         speedUnit="mph", warnings=[], explicitDuration=3,
         inputs=[dict(id=str(uuid.uuid4()), name="Camera", path=str(out / "camera.mp4"), kind="video",
                      legacyIndex=7, duration=3, offset=0, volume=1)], objects=[video, shape, group])
source = out / "groups.orrp"
source.write_text(json.dumps(p, indent=2))
run(exe, "convert", source, "--out", out / "groups.rrp")
run(exe, "convert", out / "groups.rrp", "--out", out / "reopened.orrp")
decoded = json.loads((out / "reopened.orrp").read_text())
# RRP stores the workspace ratio, rather than the native preview's pixel dimensions.
decoded["width"] = 320
decoded["height"] = 180
(out / "reopened.orrp").write_text(json.dumps(decoded, indent=2))
assert len(decoded["objects"]) == 3
assert decoded["objects"][0]["parentIndex"] == 2
for t in [0.25, 1.25, 2.25]:
    files = []
    for name in ["groups.orrp", "reopened.orrp"]:
        dest = out / f"{name}-{t}.png"
        run(exe, "snapshot", out / name, "--time", t, "--out", dest)
        files.append(run("ffmpeg", "-v", "error", "-i", dest, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
    assert len(files[0]) == 320 * 180 * 3
    assert files[0] == files[1], f"Group legacy roundtrip changed pixels at {t}"
    if t == 1.25:
        assert max(files[0]) == 0, "Hidden group's camera or overlay leaked into the snapshot"
print("PASS group gates, baked child geometry and exact native/RRP snapshot comparison", flush=True)

dest = out / "groups.mp4"
if dest.exists():
    dest.unlink()
run(exe, "export", source, "--start", 0, "--duration", 3, "--width", 320, "--out", dest)
for t, active in [(0.25, True), (1.25, False), (2.25, True)]:
    pcm = array.array("f", run("ffmpeg", "-v", "error", "-ss", t, "-i", dest, "-t", 0.25,
                              "-vn", "-ac", 1, "-f", "f32le", "-"))
    rms = math.sqrt(sum(v*v for v in pcm) / len(pcm))
    assert rms > 0.01 if active else rms < 0.0001, (t, rms)
    raw = run("ffmpeg", "-v", "error", "-ss", t, "-i", dest, "-frames:v", 1,
              "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert max(raw) > 100 if active else max(raw) < 5, (t, max(raw))
print("PASS rendered video and audio hide and resume together at group timeline boundaries", flush=True)
print(out)
