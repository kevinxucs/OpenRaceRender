#!/usr/bin/env python3
"""End-to-end compositor check. Requires ffmpeg/ffprobe only for generating/inspecting test media."""
import json, subprocess, uuid, array, math
from pathlib import Path
root = Path(__file__).resolve().parent.parent
out = root / "build" / "validation" / "features"
out.mkdir(parents=True, exist_ok=True)
def run(*args):
    return subprocess.run(list(map(str,args)), check=True, capture_output=True).stdout
for name, color, frequency, length in [("red", "red", 440, 4), ("blue", "blue", 880, 3)]:
    run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"color=c={color}:s=320x180:r=30:d={length}", "-f", "lavfi", "-i", f"sine=frequency={frequency}:sample_rate=48000:duration={length}", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", out/f"{name}.mp4")
def uid(): return str(uuid.uuid4())
def source(name, index, duration):
    return dict(id=uid(), name=name, path=str(out/f"{name}.mp4"), kind="video", offset=0, duration=duration, volume=1, legacyIndex=index)
def display(name, kind, **changes):
    obj = dict(id=uid(), name=name, kind=kind, style="", inputIndex=0, x=0, y=0, width=100, height=100, opacity=1, visible=True, channel="", text="", color="#00FF00", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    obj.update(changes)
    return obj
red, blue = source("red",0,4), source("blue",1,3)
red["timing"] = dict(trimStart=1,trimEnd=3,projectStart=0,rate=2)
blue["joinedTo"] = 0
camera = display("Joined camera", "video", segments=[dict(id=uid(),time=2,visible=False)])
shape = display("Foreground", "shape", x=5,y=5,width=10,height=10,end=0.5)
project = dict(formatVersion=1,name="Feature acceptance",width=320,height=180,fps=30,speedUnit="mph",inputs=[red,blue],objects=[camera,shape],warnings=[])
path = out/"acceptance.orrp"
path.write_text(json.dumps(project,indent=2))
exe = root/".build"/"release"/"OpenRaceRender"
for time in [0.25,1.25,2.25]:
    run(exe,"snapshot",path,"--time",time,"--out",out/f"frame-{time}.png")
video = out/"acceptance.mp4"
if video.exists(): video.unlink()
run(exe,"export",path,"--start",0,"--duration",4,"--out",video)
probe = json.loads(run("ffprobe","-v","error","-show_streams","-show_format","-of","json",video))
assert any(s["codec_type"] == "audio" for s in probe["streams"])
assert abs(float(probe["format"]["duration"])-4) < 0.1
expected = [(0.25,0),(1.25,2),(2.25,None)]
for time, channel in expected:
    frame = run("ffmpeg","-v","error","-ss",time,"-i",video,"-frames:v",1,"-f","rawvideo","-pix_fmt","rgb24","-")
    pixel = frame[(90*320+160)*3:(90*320+160)*3+3]
    if channel is None: assert max(pixel) < 20, (time,list(pixel))
    else: assert pixel[channel] > 200 and sum(pixel)-pixel[channel] < 50, (time,list(pixel))
    if time == 0.25:
        corner = frame[(162*320+32)*3:(162*320+32)*3+3]
        assert corner[1] > 200 and corner[0] < 30, list(corner)
    print(f"PASS {time}s center pixel {list(pixel)}")
print("PASS H.264/AAC, 4 seconds, trim/rate/join, overlay layer and segment visibility")

for time, audible in [(0.25, True),(2.5, False)]:
    audio = array.array("f", run("ffmpeg","-v","error","-ss",time,"-t",0.2,"-i",video,"-vn","-ac",1,"-f","f32le","-"))
    rms = math.sqrt(sum(v*v for v in audio)/max(1,len(audio)))
    assert (rms > 0.01) if audible else (rms < 0.001), (time,rms)
print("PASS audio follows camera visibility")
# Exercise input switching independently of sequential joining.
red.pop("timing"); blue.pop("joinedTo")
camera["segments"] = [dict(id=uid(),time=1,inputIndex=1)]
project["objects"] = [shape,camera]  # Camera must cover the green shape below it.
path.write_text(json.dumps(project,indent=2))
cut = out/"switching.mp4"
if cut.exists(): cut.unlink()
run(exe,"export",path,"--start",0,"--duration",2,"--out",cut)
for time, channel in [(0.25,0),(1.25,2)]:
    frame = run("ffmpeg","-v","error","-ss",time,"-i",cut,"-frames:v",1,"-f","rawvideo","-pix_fmt","rgb24","-")
    pixel = frame[(162*320+32)*3:(162*320+32)*3+3]
    assert pixel[channel] > 200 and sum(pixel)-pixel[channel] < 50, list(pixel)
print("PASS camera switching and layer order")
