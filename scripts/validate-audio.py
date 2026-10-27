#!/usr/bin/env python3
"""F23 channel-isolated stereo/mono input, independent display mixes, gates and chunks."""
import array
import copy
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/audio/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


for name, signal, codec in [("stereo", "0.04*sin(2*PI*440*t)|0.04*sin(2*PI*880*t)", "pcm_s16le"), ("stereo24", "0.04*sin(2*PI*440*t)|0.04*sin(2*PI*880*t)", "pcm_s24le"), ("mono", "0.04*sin(2*PI*440*t)", "pcm_s16le")]:
    run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=320x180:r=30:d=4",
        "-f", "lavfi", "-i", "aevalsrc="+signal+":s=48000:d=4", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", codec, "-shortest", out / f"{name}.mov")


def audio(volume=1, balance=0, routing="stereo"):
    return dict(volume=volume, balance=balance, routing=routing)


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=0,
                 x=0, y=0, width=100, height=100, opacity=1, visible=True, channel="", text="",
                 color="#5EE0B5", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


group = obj("Mix group", "group", inputIndex=-1, segments=[dict(id=str(uuid.uuid4()), time=3, visible=False)])
camera = obj("Left display", "video", parentID=group["id"], audio=audio(0.5, -1),
             segments=[dict(id=str(uuid.uuid4()), time=1, audio=audio(0)), dict(id=str(uuid.uuid4()), time=2, audio=audio(0.5, 0, "mono"))])
second = obj("Independent right display", "audio", parentID=group["id"], audio=audio(0.25, 1, "swap"),
             segments=[dict(id=str(uuid.uuid4()), time=1, audio=audio(0.5, 1, "right")), dict(id=str(uuid.uuid4()), time=2, audio=audio(0))])
p = dict(formatVersion=1, name="Independent stereo mixes", width=320, height=180, fps=30, speedUnit="m/s", warnings=[],
         inputs=[dict(id=str(uuid.uuid4()), name="Source", kind="video", path=str(out/"stereo.mov"), legacyIndex=0, duration=4, offset=0, volume=0.8, audio=audio(0.5))],
         objects=[camera, second, group])
source = out / "audio.orrp"
source.write_text(json.dumps(p, indent=2))
video = out / f"mixed-{uuid.uuid4().hex[:8]}.mp4"
chunk = out / f"chunk-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--out", video)
run(exe, "export", source, "--start", 2.15, "--duration", 0.6, "--out", chunk)


def spectrum(file, t):
    pcm = array.array("f", run("ffmpeg", "-v", "error", "-ss", t, "-i", file, "-t", 0.25, "-vn", "-ac", 2, "-ar", 48000, "-f", "f32le", "-"))
    channels = [pcm[::2], pcm[1::2]]
    values = []
    for samples in channels:
        for frequency in [440, 880]:
            real = sum(v*math.cos(2*math.pi*frequency*i/48000) for i, v in enumerate(samples))
            imaginary = sum(v*math.sin(2*math.pi*frequency*i/48000) for i, v in enumerate(samples))
            values.append(2*math.hypot(real, imaginary)/len(samples))
    return values


def check(actual, expected):
    for a, b in zip(actual, expected):
        assert abs(a-b) < max(0.0004, b*0.08), (actual, expected)


for t, expected in [(0.25, [0.008, 0, 0.004, 0]), (1.25, [0, 0, 0, 0.008]),
                    (2.25, [0.004, 0.004, 0.004, 0.004]), (3.25, [0, 0, 0, 0])]:
    check(spectrum(video, t), expected)
check(spectrum(chunk, 0.1), [0.004]*4)
high_depth = copy.deepcopy(p)
high_depth["inputs"][0]["path"] = str(out/"stereo24.mov")
high_file = out / "stereo24.orrp"
high_file.write_text(json.dumps(high_depth, indent=2))
high_video = out / f"stereo24-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", high_file, "--out", high_video)
check(spectrum(high_video, 0.25), [0.008, 0, 0.004, 0])
check(spectrum(high_video, 3.25), [0]*4)
mono = copy.deepcopy(p)
mono["inputs"][0].update(path=str(out/"mono.mov"), volume=1, audio=audio())
mono["objects"] = [dict(camera, parentID=None, audio=audio(1, -1))]
mono["objects"][0].pop("segments")
mono_file = out / "mono.orrp"
mono_file.write_text(json.dumps(mono, indent=2))
mono_video = out / f"mono-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", mono_file, "--out", mono_video)
check(spectrum(mono_video, 0.25), [0.04, 0, 0, 0])
print("Audio acceptance passed: source gain product, independent display routing/pan/gain, timeline mute/mono, hidden groups, nonzero chunks and hard-panned mono input and 24-bit stereo match channel spectra.")
