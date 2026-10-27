#!/usr/bin/env python3
"""F22 independent constant-time references, manual hold, UTC/DST and encoded chunks without CSV."""
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/timers/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=8",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "camera.mp4")


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=-1,
                 x=5, y=20, width=43, height=60, opacity=1, visible=True, channel="", text="",
                 color="#5EE0B5", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


manual = dict(mode="manual", clock="project", format="automatic", decimals=3, compact=False,
              startDelay=1, startOffset=5, stopValue=7, anchorTime=1, timeZone="UTC",
              twelveHour=False, showTimeZone=False, label="", panel=True)
wall = dict(manual, mode="timeOfDay", epoch=1710064799, timeZone="America/Los_Angeles")
p = dict(formatVersion=1, name="Manual timer and explicit clock", width=640, height=360, fps=30,
         speedUnit="m/s", warnings=[], rangeStart=0, rangeEnd=8,
         inputs=[dict(id=str(uuid.uuid4()), name="Camera", kind="video", path=str(out/"camera.mp4"), legacyIndex=0, duration=8, offset=0, volume=1)],
         objects=[obj("Camera", "video", inputIndex=0, x=0, y=0, width=100, height=100),
                  obj("Manual", "timer", timerSettings=manual), obj("Clock", "timer", x=52, timerSettings=wall)])
source = out / "timers.orrp"
source.write_text(json.dumps(p, indent=2))


def raw(image):
    return run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")


frames = {}
for t, value in [(0.5, 5), (3.3, 6.3), (4.2, 7), (6.2, 7)]:
    image = out / f"timer-{t}.png"
    run(exe, "snapshot", source, "--time", t, "--out", image)
    frame = raw(image)
    ref = copy.deepcopy(p)
    ref["objects"][1]["timerSettings"]["startOffset"] = value
    ref["objects"][1]["timerSettings"]["startDelay"] = 1e9
    ref["objects"][1]["timerSettings"].pop("stopValue")
    ref["objects"][2]["timerSettings"]["epoch"] = 1710064799+t
    reference = out / "reference.orrp"
    reference.write_text(json.dumps(ref, indent=2))
    expected_image = out / f"reference-{t}.png"
    run(exe, "snapshot", reference, "--time", 0, "--out", expected_image)
    expected = raw(expected_image)
    assert len(frame) == len(expected) == 640*360*3
    assert sum(abs(a-b) for a, b in zip(frame, expected))/len(frame) < 0.1
    frames[t] = frame
left = lambda frame: b"".join(frame[row*640*3:row*640*3+320*3] for row in range(360))
assert left(frames[4.2]) == left(frames[6.2]), "Stopped manual timer did not hold"
video = out / f"timers-{uuid.uuid4().hex[:8]}.mp4"
chunk = out / f"chunk-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--out", video)
run(exe, "export", source, "--start", 3.3, "--duration", 0.5, "--out", chunk)
full = run("ffmpeg", "-v", "error", "-ss", 3.3, "-i", video, "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
part = run("ffmpeg", "-v", "error", "-i", chunk, "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
assert len(full) == len(part) == len(frames[3.3])
assert sum(abs(a-b) for a, b in zip(full, frames[3.3]))/len(full) < 3
assert sum(abs(a-b) for a, b in zip(full, part))/len(full) < 2
invalid = copy.deepcopy(p)
invalid["objects"][2]["timerSettings"].pop("epoch")
invalid["objects"][2]["timerSettings"]["clock"] = "source"
bad = out / "missing-anchor.orrp"
bad.write_text(json.dumps(invalid, indent=2))
destination = out / f"invalid-{uuid.uuid4().hex[:8]}.mp4"
failed = subprocess.run([str(exe), "export", str(bad), "--out", str(destination)], capture_output=True)
assert failed.returncode and not destination.exists(), "Missing wall-clock anchor exported silently"
print("Timer acceptance passed: delay/offset/stop and explicit wall clock match constant references; hold, encoded/chunk frames and missing-anchor preflight pass without a telemetry file.")
print(out / "timer-3.3.png")
