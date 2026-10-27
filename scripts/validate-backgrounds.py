#!/usr/bin/env python3
"""Original F09 embedded background composition, clear/resume and encoded-video acceptance."""
import base64
import json
import math
import struct
import subprocess
import uuid
import zlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/background/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    p = subprocess.run(list(map(str, args)), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


def chunk(t, b):
    return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b))


rows = b"".join(b"\0" + b"".join(bytes((60+(x//8 % 2)*30, 80+(y//8 % 2)*30, 150, 255))
                 for x in range(64)) for y in range(64))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=3",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "camera.mp4")
(out / "data.csv").write_text("Time,Speed,X,Y\n" + "\n".join(
    f"{i/60},50,{math.cos(i/30)},{math.sin(i/30)}" for i in range(181)))


def obj(name, kind, **kw):
    o = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=1, channel="Speed", text="", color="#5EE0B5",
             minimum=0, maximum=100, x=5, y=10, width=40, height=80, opacity=1, visible=True, start=0, end=1000000, parentIndex=-1)
    o.update(kw)
    return o


art = base64.b64encode(png).decode()
map_object = obj("Map with embedded background", "map", artwork=art)
gauge = obj("Gauge with embedded background", "speed", x=55, artwork=art, gauge=dict(sweep=270, rotation=0,
    counterClockwise=False, showFace=False, showNumber=True, showLabels=True, divisions=8, decimals=0,
    numberingScale=1, label="Speed", warningColor="#FF616D"))
# An explicit empty artwork event clears the background, followed by restoration.
map_object["segments"] = [dict(id=str(uuid.uuid4()), time=1, artwork=""), dict(id=str(uuid.uuid4()), time=2, artwork=art)]
picture = dict(left=0, right=0, top=0, bottom=0, flipX=False, flipY=False, rotation=0, maintainAspect=True,
               brightness=1, contrast=1, saturation=1, sharpness=1, hue=0, legacyColorInterpretation=True)
p = dict(formatVersion=1, name="Widget background acceptance", width=640, height=360, fps=30, speedUnit="mph",
         warnings=[], explicitDuration=3, objects=[obj("Camera", "video", inputIndex=0, x=0, y=0, width=100, height=100), map_object, gauge],
         inputs=[dict(id=str(uuid.uuid4()), name="Camera", path=str(out/"camera.mp4"), kind="video", duration=3, offset=0, volume=1, legacyIndex=0, picture=picture),
                 dict(id=str(uuid.uuid4()), name="Data", path=str(out/"data.csv"), kind="data", duration=3, offset=0, volume=1, legacyIndex=1)])
source = out / "backgrounds.orrp"
source.write_text(json.dumps(p, indent=2))
frames = []
for t in [0.5, 1.5, 2.5]:
    path = out / f"backgrounds-{t}.png"
    run(exe, "snapshot", source, "--time", t, "--out", path)
    frames.append(run("ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
# A corner inside the map's background is away from the trace and dot.
index = (65*640+45)*3
assert frames[0][index:index+3] == frames[2][index:index+3]
assert frames[0][index:index+3] != frames[1][index:index+3], "Background clear event did not apply"
video = out / f"backgrounds-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--duration", 3, "--out", video)
for i, t in enumerate([0.5, 1.5, 2.5]):
    actual = run("ffmpeg", "-v", "error", "-ss", t, "-i", video, "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(actual) == len(frames[i]) == 640*360*3
    assert sum(abs(a-b) for a, b in zip(actual, frames[i]))/len(actual) < 3
print("Background acceptance passed: embedded map/gauge artwork, timeline clear/resume, encoded frames matching snapshots.")
print(out / "backgrounds-0.5.png")
