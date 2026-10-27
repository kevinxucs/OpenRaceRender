#!/usr/bin/env python3
"""Original F14 sequence gaps: picture, audio, overlays, boundaries and native reopen."""
import json
import math
import struct
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/"build/validation/sequences/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root/"build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    p = subprocess.run(list(map(str, args)), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


for name, color, tone in [("red", "0xD02020", 440), ("blue", "0x2030D0", 880)]:
    run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"color=c={color}:s=640x360:r=30:d=2",
        "-f", "lavfi", "-i", f"sine=frequency={tone}:sample_rate=48000:duration=2",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", out/f"{name}.mp4")
stream = dict(id=str(uuid.uuid4()), name="Joined camera", path="", kind="video", legacyIndex=0,
              duration=5.5, offset=0, volume=1, isJoinRoot=True)
inputs = [stream]
for i, (name, duration, gap) in enumerate([("red", 2, False), ("Middle gap", 1, True), ("blue", 2, False), ("Trailing gap", 0.5, True)], 1):
    inputs.append(dict(id=str(uuid.uuid4()), name=name, path="" if gap else str(out/f"{name}.mp4"),
                       kind="video", legacyIndex=i, duration=duration, offset=0, volume=0 if gap else 1,
                       joinedTo=0, **({"isTimeFiller":True} if gap else {})))


def obj(name, kind, **kwargs):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=0,
                 x=0, y=0, width=100, height=100, opacity=1, visible=True, channel="", text="",
                 color="#FFFFFF", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kwargs)
    return value


p = dict(formatVersion=1, name="Sequence gaps acceptance", width=640, height=360, fps=30,
         speedUnit="mph", warnings=[], lengthInputIndex=0, inputs=inputs,
         objects=[obj("Camera", "video"), obj("Continuous overlay", "shape", inputIndex=-1,
                    x=80, y=80, width=10, height=10, color="#20E060")])
source = out/"sequence.orrp"
source.write_text(json.dumps(p, indent=2))
run(exe, "convert", source, "--out", out/"reopened.orrp")
frames = []
for time in [0.5, 2.5, 3.5, 5.25]:
    image = out/f"sequence-{time}.png"
    run(exe, "snapshot", out/"reopened.orrp", "--time", time, "--out", image)
    frame = run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    frames.append(frame)
    center = frame[(180*640+320)*3:(180*640+320)*3+3]
    if time in [2.5, 5.25]:
        assert max(center) < 3, "A filler displayed a stale source frame"
    elif time == 0.5:
        assert center[0] > 150 and center[2] < 80
    else:
        assert center[2] > 150 and center[0] < 80
video = out/f"sequence-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--out", video)
duration = float(run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", video))
assert abs(duration-5.5) < 0.05, "Middle/trailing fillers did not extend output duration"
for frame, time in zip(frames, [0.5, 2.5, 3.5, 5.25]):
    actual = run("ffmpeg", "-v", "error", "-ss", time, "-i", video, "-frames:v", 1,
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(actual) == len(frame) == 640*360*3
    assert sum(abs(a-b) for a,b in zip(actual,frame))/len(frame) < 3
    pcm = run("ffmpeg", "-v", "error", "-ss", time, "-i", video, "-t", 0.1,
              "-vn", "-ac", 1, "-f", "f32le", "-")
    samples = struct.unpack("<"+"f"*(len(pcm)//4), pcm)
    assert samples or time == 5.25, "Audio disappeared before the last clip ended"
    rms = math.sqrt(sum(x*x for x in samples)/len(samples)) if samples else 0
    assert rms < 0.001 if time in [2.5, 5.25] else rms > 0.02, "Filler audio was not silent or clip audio was lost"
for start in [2.25, 5.0]:
    chunk = out/f"gap-only-{start}-{uuid.uuid4().hex[:8]}.mp4"
    run(exe, "export", source, "--start", start, "--duration", 0.5, "--out", chunk)
    actual = run("ffmpeg", "-v", "error", "-ss", 0.25, "-i", chunk, "-frames:v", 1,
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(actual) == len(frames[1])
    assert sum(abs(a-b) for a,b in zip(actual,frames[1]))/len(actual) < 3, "A gap-only export lost its picture/overlay clock"
print("Sequence acceptance passed: ordered clips, middle/trailing picture+audio gaps, continuing overlay and native reopen.")
print(out/"sequence-2.5.png")
