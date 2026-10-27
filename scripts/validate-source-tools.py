#!/usr/bin/env python3
"""Original F11 media acceptance: physical trim, pixel crop, marks and encoded frames."""
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/source-tools/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    p = subprocess.run(list(map(str, args)), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=640x360:r=30:d=4",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "source.mp4")
picture = dict(left=0.25, right=0.25, top=0.25, bottom=0.25, flipX=False, flipY=False,
               rotation=0, maintainAspect=True, brightness=1, contrast=1, saturation=1,
               sharpness=1, hue=0, legacyColorInterpretation=True)
o = dict(id=str(uuid.uuid4()), name="Camera", kind="video", style="", inputIndex=0,
         x=0, y=0, width=100, height=100, opacity=1, visible=True, channel="", text="",
         color="#FFFFFF", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
p = dict(formatVersion=1, name="Visual source editing acceptance", width=640, height=360,
         fps=30, speedUnit="mph", warnings=[], rangeStart=0.5, rangeEnd=1.5, objects=[o],
         inputs=[dict(id=str(uuid.uuid4()), name="Camera", path=str(out/"source.mp4"),
                      kind="video", duration=4, offset=0, volume=1, legacyIndex=0,
                      picture=picture, timing=dict(trimStart=1, trimEnd=3, projectStart=0, rate=1))])
source = out / "trim-crop.orrp"
source.write_text(json.dumps(p, indent=2))
run(exe, "convert", source, "--out", out/"trim-crop.rrp")
run(exe, "convert", out/"trim-crop.rrp", "--out", out/"reopened.orrp")
reopened = json.loads((out/"reopened.orrp").read_text())
assert abs(reopened["rangeStart"]-0.5) < 1e-6 and abs(reopened["rangeEnd"]-1.5) < 1e-6
raw = copy.deepcopy(p)
raw["inputs"][0].pop("timing")
(out/"untrimmed.orrp").write_text(json.dumps(raw))


def snapshot(project, time, name):
    path = out / name
    run(exe, "snapshot", project, "--time", time, "--width", 640, "--height", 360, "--out", path)
    return run("ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")


frames = []
for t in [0.5, 1.0]:
    frame = snapshot(source, t, f"edited-{t}.png")
    frames.append(frame)
    assert frame == snapshot(out/"untrimmed.orrp", t+1, f"physical-{t+1}.png"), "Trim uses wrong physical source frame"
    legacy = snapshot(out/"trim-crop.rrp", t, f"legacy-{t}.png")
    assert sum(abs(a-b) for a,b in zip(legacy,frame))/len(frame) < 1, "Legacy trim/crop changed appearance"
assert frames[0] != frames[1], "Source video did not advance"
video = out / f"marked-export-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--out", video)
duration = float(run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", video))
assert abs(duration-1) < 0.05, "Source trim replaced project In/Out bounds"
for i,t in enumerate([0, 0.5]):
    actual = run("ffmpeg", "-v", "error", "-ss", t, "-i", video, "-frames:v", 1,
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(actual) == len(frames[i]) == 640*360*3
    assert sum(abs(a-b) for a,b in zip(actual,frames[i]))/len(actual) < 4, "Encoded crop/trim differs from snapshot"
print("Source tools acceptance passed: physical frames, crop, legacy reopening, project marks and encoded output.")
print(out / "edited-0.5.png")
