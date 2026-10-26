#!/usr/bin/env python3
"""End-to-end compositor check. Requires ffmpeg/ffprobe only for generating/inspecting test media."""
import json, subprocess, uuid, array, math, struct, zipfile
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

# A partial export must start at zero in the output while reading the chosen
# camera/audio at the requested project time, with the exact fractional FPS.
partial = out/"partial.mp4"
if partial.exists(): partial.unlink()
run(exe,"export",path,"--start",1.25,"--duration",0.5,"--fps",60000/1001,
    "--video-bitrate",800,"--audio-bitrate",128,"--out",partial)
metadata = json.loads(run("ffprobe","-v","error","-show_streams","-show_format","-of","json",partial))
v = next(s for s in metadata["streams"] if s["codec_type"] == "video")
a = next(s for s in metadata["streams"] if s["codec_type"] == "audio")
assert v["profile"] == "High" and v["r_frame_rate"] == "60000/1001", v
assert v["color_space"] == "bt709" and v["color_primaries"] == "bt709", v
assert a["sample_rate"] == "48000" and a["channels"] == 2, a
assert abs(float(metadata["format"]["duration"])-0.5) < 0.05, metadata["format"]
frame = run("ffmpeg","-v","error","-i",partial,"-frames:v",1,"-f","rawvideo","-pix_fmt","rgb24","-")
pixel = frame[(90*320+160)*3:(90*320+160)*3+3]
assert pixel[2] > 200 and pixel[0] < 30 and pixel[1] < 30, list(pixel)
audio = array.array("f",run("ffmpeg","-v","error","-i",partial,"-vn","-ac",1,"-f","f32le","-"))
assert math.sqrt(sum(x*x for x in audio)/max(1,len(audio))) > 0.01
print("PASS nonzero range, fractional FPS, High Profile, Rec.709 tags and stereo AAC")

# Opening a saved project and exporting without CLI range flags must honor its
# In/Out marks, even when an older remembered export covered another span.
project["rangeStart"], project["rangeEnd"] = 1.25, 1.75
project["lastExport"] = dict(path="previous.mp4", start=0, duration=4)
path.write_text(json.dumps(project, indent=2))
marked = out/"marked.mp4"
if marked.exists(): marked.unlink()
run(exe, "export", path, "--out", marked)
metadata = json.loads(run("ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", marked))
assert abs(float(metadata["format"]["duration"])-0.5) < 0.05
frame = run("ffmpeg", "-v", "error", "-i", marked, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
pixel = frame[(90*320+160)*3:(90*320+160)*3+3]
assert pixel[2] > 200 and pixel[0] < 30 and pixel[1] < 30, list(pixel)
print("PASS saved In/Out marks override remembered ranges and CLI exports default to the marked span")

# Use the actual RRP3 header/input fields to test import through file export,
# rather than only assigning marks and picture settings to a native JSON file.
legacy = bytearray(2152 + 2216 + 56 + 348)
legacy[:4] = b"RRP3"
for offset, value in [(12,2152),(16,1),(20,2216),(28,56),(32,1),(36,344)]:
    struct.pack_into("<I", legacy, offset, value)
struct.pack_into("<ff", legacy, 2128, 1.25, 1.75)
def utf16(offset, length, text):
    encoded = str(text).encode("utf-16le")
    assert len(encoded) < length
    legacy[offset:offset+length] = encoded + bytes(length-len(encoded))
utf16(2152,128,"Red camera"); utf16(2152+128,2048,out/"red.mp4")
struct.pack_into("<f",legacy,2152+2184,4)
settings = 2152+2216
legacy[settings] = 100; legacy[settings+1] = 100
legacy[settings+25:settings+28] = bytes([100,100,100])
struct.pack_into("<h",legacy,settings+28,120)
legacy[settings+30] = 150
obj = settings+56
utf16(obj,128,"Camera"); struct.pack_into("<i",legacy,obj+256,-1)
struct.pack_into("<ffff",legacy,obj+260,0,0,100,100)
legacy[obj+280:obj+286] = bytes([10,2,0,0,1,0]); legacy[obj+292:obj+294] = bytes([100,100])
legacy_path = out/"marked-hue.rrp"; legacy_path.write_bytes(legacy)
converted = out/"marked-hue.orrp"
run(exe,"convert",legacy_path,"--out",converted)
saved = json.loads(converted.read_text())
assert (saved["rangeStart"],saved["rangeEnd"]) == (1.25,1.75)
assert saved["inputs"][0]["picture"]["hue"] == 120
assert saved["inputs"][0]["picture"]["sharpness"] == 1.5
result = out/"marked-hue.mp4"
if result.exists(): result.unlink()
run(exe,"export",legacy_path,"--width",320,"--out",result)
metadata = json.loads(run("ffprobe","-v","error","-show_format","-of","json",result))
assert abs(float(metadata["format"]["duration"])-0.5) < 0.05
frame = run("ffmpeg","-v","error","-i",result,"-frames:v",1,"-f","rawvideo","-pix_fmt","rgb24","-")
pixel = frame[(90*320+160)*3:(90*320+160)*3+3]
assert pixel[1] > 220 and pixel[0] < 35 and pixel[2] < 35, list(pixel)
print("PASS RRP marker import, native save, hue/sharpness import, marked-range export and rendered hue")

# Missing inputs must not silently become blank cameras or zero-value gauges.
# Only dependencies used inside the chosen range should block an export.
recovery = json.loads(json.dumps(project))
recovery.pop("rangeStart"); recovery.pop("rangeEnd")
recovery["inputs"][1]["path"] = str(out/"missing-camera.mp4")
recovery_path = out/"missing-camera.orrp"
recovery_path.write_text(json.dumps(recovery))
def rejected(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    assert result.returncode != 0, result.stdout
    assert b"Relink the missing assets" in result.stderr, result.stderr
blocked = out/"missing-source-output.mp4"
if blocked.exists(): blocked.unlink()
rejected(exe,"export",recovery_path,"--start",1,"--duration",0.5,"--out",blocked)
assert not blocked.exists()
rejected(exe,"snapshot",recovery_path,"--time",1.25,"--out",out/"missing-source-frame.png")
run(exe,"snapshot",recovery_path,"--time",0.99,"--out",out/"before-missing-source.png")
unaffected = out/"available-range.mp4"
if unaffected.exists(): unaffected.unlink()
run(exe,"export",recovery_path,"--start",0,"--duration",0.5,"--out",unaffected)
frame = run("ffmpeg","-v","error","-i",unaffected,"-frames:v",1,"-f","rawvideo","-pix_fmt","rgb24","-")
pixel = frame[(90*320+160)*3:(90*320+160)*3+3]
assert pixel[0] > 200 and pixel[1] < 30 and pixel[2] < 30, list(pixel)
recovery["inputs"][1]["path"] = str(out/"blue.mp4")
recovery["inputs"].append(dict(id=uid(),name="Missing telemetry",path=str(out/"missing.csv"),kind="data",offset=0,duration=4,volume=1,legacyIndex=2))
recovery["objects"].append(display("Speed","speed",inputIndex=2,width=20,height=20))
recovery_path.write_text(json.dumps(recovery))
rejected(exe,"export",recovery_path,"--start",1,"--duration",0.5,"--out",blocked)
assert not blocked.exists()
print("PASS missing camera/telemetry preflight, no incomplete output, snapshot preflight and unaffected export ranges")

# RCZ uses binary device/individual-channel clocks. Equivalent CSV and RCZ
# sources must produce the same overlay pixels through snapshot and video export.
rcz = out/"telemetry.rcz"
base = 1_700_000_000_000
clock = struct.pack("<4q", *(base+i*1000 for i in range(4)))
with zipfile.ZipFile(rcz,"w",compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("session.json",json.dumps({"title":"Synthetic render telemetry"}))
    archive.writestr("channel_1_42_0_1_1",clock)
    archive.writestr("channel_1_42_0_4_0",struct.pack("<4i",10000,20000,30000,40000))
    archive.writestr("channel_12_88_10024_1_1",clock)
    archive.writestr("channel2_12_88_10024_10024_3",struct.pack("<4d",1000,2000,3000,4000))
    for channel, values in [(7,[0,0.5,0,-0.5]),(8,[0.5,0,-0.5,0])]:
        archive.writestr(f"channel_12_88_{channel}_1_1",clock)
        archive.writestr(f"channel2_12_88_{channel}_{channel}_3",struct.pack("<4d",*(v*9.80665 for v in values)))
csv_source = out/"equivalent-telemetry.csv"
csv_source.write_text("Time,Speed (m/s),RPM,Longitudinal acceleration (g) *calc,Lateral acceleration (g) *calc\n0,10,1000,0.5,0\n1,20,2000,0,0.5\n2,30,3000,-0.5,0\n3,40,4000,0,-0.5\n")
telemetry_source = dict(id=uid(),name="Telemetry",path=str(rcz),kind="data",offset=0,duration=3,volume=1,legacyIndex=9)
render_project = dict(formatVersion=1,name="RCZ render acceptance",width=320,height=180,fps=30,speedUnit="mph",inputs=[source("red",0,4),telemetry_source],
    objects=[display("Camera","video"),display("Speed","speed",inputIndex=9,x=5,y=5,width=30,height=50),display("G-force","gforce",inputIndex=9,x=70,y=5,width=25,height=45)],warnings=[])
for format, source_file in [("rcz",rcz),("csv",csv_source)]:
    telemetry_source["path"] = str(source_file)
    project_file = out/f"{format}-render.orrp"
    project_file.write_text(json.dumps(render_project))
    run(exe,"snapshot",project_file,"--time",1.25,"--out",out/f"{format}-overlay.png")
    target = out/f"{format}-render.mp4"
    if target.exists():target.unlink()
    run(exe,"export",project_file,"--start",0.5,"--duration",1,"--out",target)
assert (out/"rcz-overlay.png").read_bytes() == (out/"csv-overlay.png").read_bytes()
for at in [0.1,0.5,0.9]:
    frames = [run("ffmpeg","-v","error","-ss",at,"-i",out/f"{format}-render.mp4","-frames:v",1,"-f","rawvideo","-pix_fmt","rgb24","-") for format in ["rcz","csv"]]
    assert len(frames[0]) == len(frames[1]) == 320*180*3
    error = sum(abs(a-b) for a,b in zip(*frames))/len(frames[0])
    assert error < 0.5, (at,error)
print("PASS RCZ binary import, matching CSV snapshot pixels and matching rendered video overlays")
