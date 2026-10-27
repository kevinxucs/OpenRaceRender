#!/usr/bin/env python3
"""F17: mapped millisecond logger vs independent canonical data, still + encoded output."""
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/data-profiles/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=6",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "camera.mp4")
raw = ["Ticks,Velocity,Engine,Precision,Height,Thermal,Circuit"]
canonical = ["Time,Speed (m/s),RPM,GPS accuracy,Altitude,Adjusted coolant,Lap"]
for i in range(61):
    t = i / 10
    raw.append(f"{5000+i*100},{(10+t)*3.6},{2000+t*100},{10+t},{50+t},{70+t},{1+int(t/2)}")
    canonical.append(f"{t},{10+t},{2000+t*100},{1+t/10},{50+t},{75+t},{1+int(t/2)}")
(out / "logger.csv").write_text("\n".join(raw)+"\n")
(out / "canonical.csv").write_text("\n".join(canonical)+"\n")
settings = dict(assignments=dict(time="Ticks", speed="Velocity", rpm="Engine", accuracy="Precision",
                                 altitude="Height", coolant="Thermal", lap="Circuit"),
                fields=[dict(id=str(uuid.uuid4()), name="Adjusted coolant", source="coolant", multiply=1, add=5)],
                timeUnitsPerSecond=1000, speedConversionEnabled=True, speedMultiplier=1,
                speedUnit="km/h", accuracyMultiplier=0.1)
profile = dict(formatVersion=1, name="Original test logger", settings=settings, includesTrackSettings=False)
(out / "logger.orrd").write_text(json.dumps(profile, indent=2))


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=1,
                 x=5, y=10, width=25, height=70, opacity=1, visible=True, channel="", text="",
                 color="#5EE0B5", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


p = dict(formatVersion=1, name="Data profile comparison", width=640, height=360, fps=30,
         speedUnit="m/s", warnings=[], rangeStart=2, rangeEnd=3,
         inputs=[dict(id=str(uuid.uuid4()), name="Camera", kind="video", path=str(out/"camera.mp4"),
                      legacyIndex=0, duration=6, offset=0, volume=1),
                 dict(id=str(uuid.uuid4()), name="Logger", kind="data", path=str(out/"logger.csv"),
                      legacyIndex=1, duration=6, offset=0, volume=1, dataSettings=profile["settings"])],
         objects=[obj("Camera", "video", inputIndex=0, x=0, y=0, width=100, height=100),
                  obj("Speed", "speed"), obj("Coolant", "gauge", x=35, channel="Adjusted coolant"),
                  obj("GPS accuracy", "graph", x=65, y=55, height=40, channel="accuracy", maximum=3),
                  obj("Height", "gauge", x=65, y=5, height=40, channel="altitude", maximum=100)])
mapped = out / "mapped.orrp"
mapped.write_text(json.dumps(p, indent=2))
ref = copy.deepcopy(p)
ref["inputs"][1]["path"] = str(out / "canonical.csv")
ref["inputs"][1].pop("dataSettings")
reference = out / "reference.orrp"
reference.write_text(json.dumps(ref, indent=2))
expected = []
for t in [2.3, 2.6]:
    frames = []
    for file, label in [(mapped, "mapped"), (reference, "reference")]:
        image = out / f"{label}-{t}.png"
        run(exe, "snapshot", file, "--time", t, "--out", image)
        frames.append(run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"))
    assert len(frames[0]) == len(frames[1]) == 640*360*3
    assert sum(abs(a-b) for a, b in zip(*frames))/len(frames[0]) < 0.2, "Mapped widgets disagree with canonical data"
    expected.append(frames[0])
video = out / f"mapped-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", mapped, "--out", video)
for frame, t in zip(expected, [0.3, 0.6]):
    actual = run("ffmpeg", "-v", "error", "-ss", t, "-i", video, "-frames:v", 1,
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(actual) == len(frame)
    assert sum(abs(a-b) for a, b in zip(frame, actual))/len(frame) < 3
print("Data-profile acceptance passed: mapped clocks, speed/accuracy conversions and calculated fields match canonical snapshots and encoded frames.")
print(out / "mapped-2.3.png")
