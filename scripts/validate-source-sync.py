#!/usr/bin/env python3
"""Original F13 two-camera event alignment and encoded-video acceptance."""
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/"build/validation/source-sync/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root/"build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    p = subprocess.run(list(map(str, args)), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


for name, duration, event in [("reference", 4, 1), ("target", 6, 3)]:
    run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
        f"color=c=0x203060:s=320x180:r=30:d={duration}", "-vf",
        f"drawbox=x=0:y=0:w=iw:h=ih:color=white:t=fill:enable='between(t,{event},{event+0.3})'",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", out/f"{name}.mp4")
picture = dict(left=0, right=0, top=0, bottom=0, flipX=False, flipY=False, rotation=0,
               maintainAspect=True, brightness=1, contrast=1, saturation=1,
               sharpness=1, hue=0, legacyColorInterpretation=True)
objects = [dict(id=str(uuid.uuid4()), name=name, kind="video", style="", inputIndex=i,
                x=i*50, y=0, width=50, height=100, opacity=1, visible=True, channel="", text="",
                color="#FFFFFF", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1,
                picture={k:v for k,v in picture.items() if k not in ["sharpness", "hue", "legacyColorInterpretation"]})
           for i, name in enumerate(["Reference", "Target"])]
p = dict(formatVersion=1, name="Camera event alignment", width=640, height=360, fps=30,
         speedUnit="mph", warnings=[], rangeStart=0.5, rangeEnd=2, lengthInputIndex=0, objects=objects,
         inputs=[dict(id=str(uuid.uuid4()), name=name, path=str(out/f"{name}.mp4"), kind="video",
                      legacyIndex=i, duration=duration, offset=offset, volume=0, picture=picture)
                 for i, (name, duration, offset) in enumerate([("reference", 4, 0), ("target", 6, 2)])])
source = out/"synchronized.orrp"
source.write_text(json.dumps(p, indent=2))
run(exe, "convert", source, "--out", out/"synchronized.rrp")
frames = []
for t in [0.9, 1.1, 1.6]:
    pair = []
    for file, prefix in [(source, "native"), (out/"synchronized.rrp", "legacy")]:
        image = out/f"{prefix}-{t}.png"
        run(exe, "snapshot", file, "--time", t, "--width", 640, "--height", 360, "--out", image)
        pair.append(run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
    assert len(pair[0]) == len(pair[1]) == 640*360*3
    assert sum(abs(a-b) for a,b in zip(*pair))/len(pair[0]) < 1
    def pixel(x, y):
        i = (y*640+x)*3
        return pair[0][i:i+3]
    a, b = pixel(160, 180), pixel(480, 180)
    assert sum(abs(x-y) for x,y in zip(a,b)) < 6, "Camera events were not synchronized"
    assert (min(a) > 230) == (t == 1.1), "The flash event occurred at the wrong project time"
    frames.append(pair[0])
video = out/f"synchronized-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--out", video)
for expected, t in zip(frames, [0.4, 0.6, 1.1]):
    actual = run("ffmpeg", "-v", "error", "-ss", t, "-i", video, "-frames:v", 1,
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(actual) == len(expected)
    assert sum(abs(a-b) for a,b in zip(actual,expected))/len(actual) < 3
print("Camera sync acceptance passed: matching visible events, legacy reopening, marked export and encoded frames.")
print(out/"native-1.1.png")
