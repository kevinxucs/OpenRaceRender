#!/usr/bin/env python3
"""Original artwork/data F08 acceptance: mapping, flashing, interop and encoded video."""
import base64
import copy
import json
import struct
import subprocess
import uuid
import zlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/image-controls/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


# An asymmetric, original transparent arrow: no external artwork or private data.
size = 96
rows = b"".join(b"\0" + b"".join(bytes((255, 140 if x < 48 else 30, 20,
                 255 if y > x//2 and y < 90 else 0)) for x in range(size)) for y in range(size))
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
(out / "arrow.png").write_bytes(png)
run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=5",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "camera.mp4")
(out / "data.csv").write_text("Time,Level\n" + "\n".join(f"{i/60},{i/3.6}" for i in range(361)))


def display(name, kind, **settings):
    result = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=1, channel="Level",
                  text="", color="#5EE0B5", minimum=0, maximum=100, x=5, y=5, width=25, height=35,
                  opacity=1, visible=True, start=0, end=1000000, parentIndex=-1)
    result.update(settings)
    return result


objects = [display("Camera", "video", inputIndex=0, x=0, y=0, width=100, height=100)]
for i, output in enumerate(["opacity", "rotation", "brightness", "hue", "opacity", "opacity"]):
    control = dict(mode="proportional", output=output, inputMinimum=0, inputMaximum=100,
                   outputMinimum=0, outputMaximum=100, pulseInterval=0)
    if output == "rotation":
        control.update(outputMaximum=360)
    elif output == "brightness":
        control.update(outputMinimum=50, outputMaximum=150)
    elif output == "hue":
        control.update(outputMaximum=180)
    if i == 4:
        control.update(mode="greaterOrEqual", inputMaximum=50, pulseInterval=0.3)
    if i == 5:
        control.update(mode="simple", pulseInterval=0.4)
    objects.append(display(f"Image {i+1}: {output}", "image", x=4+(i % 3)*33, y=8+(1-i//3)*48,
                           embeddedImage=base64.b64encode(png).decode(), imageControl=control))
picture = dict(left=0, right=0, top=0, bottom=0, flipX=False, flipY=False, rotation=0,
               maintainAspect=True, brightness=1, contrast=1, saturation=1, sharpness=1,
               hue=0, legacyColorInterpretation=True)
p = dict(formatVersion=1, name="Image control acceptance", width=640, height=360, fps=30,
         speedUnit="mph", warnings=[], explicitDuration=5, objects=objects,
         inputs=[dict(id=str(uuid.uuid4()), name="Camera", path=str(out / "camera.mp4"), kind="video",
                      legacyIndex=0, duration=5, offset=0, volume=1, picture=picture),
                 dict(id=str(uuid.uuid4()), name="Logger", path=str(out / "data.csv"), kind="data",
                      legacyIndex=1, duration=6, offset=0.5, volume=1)])
source = out / "images.orrp"
source.write_text(json.dumps(p, indent=2))
run(exe, "convert", source, "--out", out / "images.rrp")
run(exe, "convert", out / "images.rrp", "--out", out / "reopened.orrp")
reopened = json.loads((out / "reopened.orrp").read_text())
reopened.update(width=640, height=360)
(out / "reopened.orrp").write_text(json.dumps(reopened))
for t in [0.25, 0.5, 1.25, 3.25]:
    frames = []
    for name in ["images.orrp", "reopened.orrp"]:
        dest = out / f"{name}-{t}.png"
        run(exe, "snapshot", out / name, "--time", t, "--out", dest)
        frames.append(run("ffmpeg", "-v", "error", "-i", dest, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
    assert frames[0] == frames[1], f"Image legacy roundtrip changed pixels at {t}"
# Export a nonzero-start chunk. Its flashing must use session time, not chunk time zero.
video = out / f"images-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--start", 1, "--duration", 2, "--out", video)
metadata = json.loads(run("ffprobe", "-v", "error", "-show_streams", "-of", "json", video))
track = next(t for t in metadata["streams"] if t["codec_type"] == "video")
assert 1.9 < float(track["duration"]) < 2.1
for local in [0.0, 0.5, 1.0]:
    encoded = run("ffmpeg", "-v", "error", "-ss", local, "-i", video, "-frames:v", 1,
                  "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    expected_png = out / f"chunk-reference-{local}.png"
    run(exe, "snapshot", source, "--time", 1+local, "--out", expected_png)
    expected = run("ffmpeg", "-v", "error", "-i", expected_png, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(encoded) == len(expected) == 640*360*3
    error = sum(abs(a-b) for a, b in zip(encoded, expected))/len(expected)
    assert error < 3, f"Nonzero-start image composition differs from snapshot: {error:.3f}"
print("Image controls passed: six original-art configurations, exact legacy snapshot roundtrips, synchronized nonzero-start video.")
print(out / "images.orrp-3.25.png")
