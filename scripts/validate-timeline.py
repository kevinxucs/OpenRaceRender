#!/usr/bin/env python3
"""Original F10 encoded-video check for explicit typed-parameter clear and restore."""
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/timeline-editing/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    p = subprocess.run(list(map(str, args)), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x172332:s=640x360:r=30:d=3",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", out / "camera.mp4")
(out / "data.csv").write_text("Time,Speed (km/h)\n0,50\n1,50\n2,50\n3,50\n")
run(exe, "make-template", "apex", "--out", out / "apex.orrt")
layout = json.loads((out / "apex.orrt").read_text())
o = next(o for o in layout["objects"] if o["name"] == "Speed")
o.update(x=20, y=20, width=60, height=60, inputIndex=1, channel="Speed (km/h)")
assert o.get("hud") is not None
saved = copy.deepcopy(o["hud"])
o["segments"] = [dict(id=str(uuid.uuid4()), time=1, clearedProperties=["hud"]),
                 dict(id=str(uuid.uuid4()), time=2, hud=saved)]
video_object = dict(id=str(uuid.uuid4()), name="Camera", kind="video", style="", inputIndex=0, x=0, y=0,
    width=100, height=100, opacity=1, visible=True, channel="", text="", color="#FFFFFF", minimum=0, maximum=100,
    start=0, end=1000000, parentIndex=-1)
p = dict(formatVersion=1, name="Timeline parameter acceptance", width=640, height=360, fps=30,
         speedUnit="mph", warnings=[], explicitDuration=3, objects=[video_object, o],
         inputs=[dict(id=str(uuid.uuid4()), name=name, path=str(out/file), kind=kind, legacyIndex=i,
                      duration=3, offset=0, volume=1) for i, (name,file,kind) in enumerate([
                          ("Camera","camera.mp4","video"), ("Data","data.csv","data")])])
source = out / "timeline.orrp"
source.write_text(json.dumps(p, indent=2))
frames = []
for t in [0.5,1.5,2.5]:
    file = out / f"timeline-{t}.png"
    run(exe,"snapshot",source,"--time",t,"--out",file)
    frames.append(run("ffmpeg","-v","error","-i",file,"-f","rawvideo","-pix_fmt","rgb24","-"))
assert frames[0] == frames[2], "Restored HUD parameters differ from their original appearance"
assert frames[0] != frames[1], "Explicitly cleared HUD parameters were inherited instead"
video = out / f"timeline-{uuid.uuid4().hex[:8]}.mp4"
run(exe,"export",source,"--duration",3,"--out",video)
for i,t in enumerate([0.5,1.5,2.5]):
    actual = run("ffmpeg","-v","error","-ss",t,"-i",video,"-frames:v",1,"-f","rawvideo","-pix_fmt","rgb24","-")
    assert len(actual) == len(frames[i]) == 640*360*3
    assert sum(abs(a-b) for a,b in zip(actual,frames[i]))/len(actual) < 3
print("Timeline acceptance passed: parameter clear/restore, seek-independent snapshots, matching encoded frames.")
print(out / "timeline-1.5.png")
