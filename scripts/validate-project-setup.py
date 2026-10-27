#!/usr/bin/env python3
"""Original F12 media acceptance: selected primary length follows a changed trim."""
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/project-setup/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    p = subprocess.run(list(map(str, args)), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=640x360:r=30:d=3",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out/"primary.mp4")
(out/"long-data.csv").write_text("Time,Speed (km/h)\n0,40\n5,60\n10,50\n")
o = dict(id=str(uuid.uuid4()), name="Primary camera", kind="video", style="", inputIndex=0,
         x=0, y=0, width=100, height=100, opacity=1, visible=True, channel="", text="",
         color="#FFFFFF", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
p = dict(formatVersion=1, name="Primary input length", width=640, height=360, fps=30,
         speedUnit="km/h", notes="Original setup validation", lengthInputIndex=0, warnings=[], objects=[o],
         inputs=[dict(id=str(uuid.uuid4()), name="Primary", path=str(out/"primary.mp4"), kind="video",
                      legacyIndex=0, duration=3, offset=0, volume=1,
                      timing=dict(trimStart=0.5, trimEnd=2.5, projectStart=0, rate=1)),
                 dict(id=str(uuid.uuid4()), name="Long logger", path=str(out/"long-data.csv"),
                      kind="data", legacyIndex=1, duration=10, offset=0, volume=1)])
for end, duration in [(2.5, 2), (1.5, 1)]:
    p["inputs"][0]["timing"]["trimEnd"] = end
    source = out/f"primary-{duration}.orrp"
    source.write_text(json.dumps(p, indent=2))
    result = json.loads(run(exe, "inspect", source))
    assert result["inputs"][1]["duration"] == 10, "The fixture must retain its longer telemetry source"
    video = out/f"primary-{duration}-{uuid.uuid4().hex[:8]}.mp4"
    run(exe, "export", source, "--out", video)
    actual = float(run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", video))
    assert abs(actual-duration) < 0.05, "Encoded duration did not follow the selected input trim"
    snapshot = out/f"primary-{duration}.png"
    run(exe, "snapshot", source, "--time", 0.5, "--out", snapshot)
    expected = run("ffmpeg", "-v", "error", "-i", snapshot, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    actual = run("ffmpeg", "-v", "error", "-ss", 0.5, "-i", video, "-frames:v", 1,
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(actual) == len(expected) == 640*360*3
    assert sum(abs(a-b) for a,b in zip(actual,expected))/len(actual) < 4
print("Project setup acceptance passed: bound input length follows trim and encoded video matches snapshots.")
