#!/usr/bin/env python3
"""F24 key-before-adjustment/tint, source/display agreement, spectrum and encoded timeline."""
import colorsys
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/validation/picture-effects/acceptance"
out.mkdir(parents=True, exist_ok=True)
exe = root / "build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender"


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


def ppm(name, row):
    file = out / (name+".ppm")
    file.write_bytes(b"P6\n320 180\n255\n"+row*180)
    return file


background = ppm("background", bytes([32, 64, 192])*320)
foreground = ppm("foreground", bytes([0, 255, 0])*160+bytes([255, 0, 0])*160)
for source, destination, codec in [(background, "background.mp4", ["-c:v", "libx264", "-pix_fmt", "yuv420p"]),
                                    (foreground, "foreground.mov", ["-c:v", "libx264", "-crf", "10", "-pix_fmt", "yuv420p"])]:
    run("ffmpeg", "-v", "error", "-y", "-loop", "1", "-i", source, "-t", "3", "-r", "30", "-vf", "scale=out_color_matrix=bt709",
        *codec, "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", out/destination)


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style="", inputIndex=-1,
                 x=0, y=0, width=100, height=100, opacity=1, visible=True, channel="", text="",
                 color="#5EE0B5", minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


effect = dict(left=0, right=0, top=0, bottom=0, flipX=False, flipY=False, rotation=0, maintainAspect=True,
              brightness=0.6, contrast=1, saturation=1,
              chromaKey=dict(color="#00FF00", colorTolerance=0.05, brightnessTolerance=0.05, softness=0.01),
              colorize=dict(mode="tint", color="#FFFF00", amount=1))
without_key = copy.deepcopy(effect)
without_key.pop("chromaKey")
p = dict(formatVersion=1, name="Picture effects", width=320, height=180, fps=30, speedUnit="m/s", warnings=[], rangeStart=1, rangeEnd=2,
         inputs=[dict(id=str(uuid.uuid4()), name=name, kind="video", path=str(out/file), legacyIndex=i, duration=3, offset=0, volume=1)
                 for i, (name, file) in enumerate([("Background", "background.mp4"), ("Foreground", "foreground.mov")])],
         objects=[obj("Background", "video", inputIndex=0), obj("Keyed tint", "video", inputIndex=1, picture=effect,
                  segments=[dict(id=str(uuid.uuid4()), time=1.5, picture=without_key)])])
source = out / "effects.orrp"
source.write_text(json.dumps(p, indent=2))


def raw(image):
    return run("ffmpeg", "-v", "error", "-i", image, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")


expected = []
for t, x, width in [(1.3, 50, 50), (1.8, 0, 100)]:
    image = out / f"effects-{t}.png"
    run(exe, "snapshot", source, "--time", t, "--out", image)
    actual = raw(image)
    ref = copy.deepcopy(p)
    ref["objects"][1] = obj("Independent tinted rectangle", "shape", x=x, width=width, color="#999900")
    file = out / "reference.orrp"
    file.write_text(json.dumps(ref, indent=2))
    reference = out / f"reference-{t}.png"
    run(exe, "snapshot", file, "--time", t, "--out", reference)
    pixels = raw(reference)
    assert len(actual) == len(pixels) == 320*180*3
    error = sum(abs(a-b) for a, b in zip(actual, pixels))/len(actual)
    assert error < 2, ("Key/tint order, transparency or timeline differs from reference", error)
    expected.append(actual)
input_effect = copy.deepcopy(p)
input_effect["inputs"][1]["picture"] = effect
input_effect["objects"][1].pop("picture")
input_effect["objects"][1].pop("segments")
file = out / "input-effects.orrp"
file.write_text(json.dumps(input_effect, indent=2))
image = out / "input-effects.png"
run(exe, "snapshot", file, "--time", 1.3, "--out", image)
assert raw(image) == expected[0], "Input and display effects disagree"
video = out / f"effects-{uuid.uuid4().hex[:8]}.mp4"
run(exe, "export", source, "--out", video)
for frame, t in zip(expected, [0.3, 0.8]):
    encoded = run("ffmpeg", "-v", "error", "-ss", t, "-i", video, "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    assert len(encoded) == len(frame)
    assert sum(abs(a-b) for a, b in zip(encoded, frame))/len(frame) < 3
# Independent HSV reference for a grayscale image's full-spectrum colorization.
levels = [0, 64, 128, 192, 255]
gray = ppm("gray", b"".join(bytes([v, v, v])*64 for v in levels))
png = out / "gray.png"
run("ffmpeg", "-v", "error", "-y", "-i", gray, png)
spectrum_effect = copy.deepcopy(effect)
spectrum_effect.update(brightness=1, colorize=dict(mode="spectrum", color="#FFFFFF", amount=1))
spectrum_effect.pop("chromaKey")
spec = copy.deepcopy(p)
spec["objects"] = [spec["objects"][0], obj("Spectrum image", "image", text=str(png), picture=spectrum_effect)]
file = out / "spectrum.orrp"
file.write_text(json.dumps(spec, indent=2))
image = out / "spectrum.png"
run(exe, "snapshot", file, "--time", 1.3, "--out", image)
ref = copy.deepcopy(spec)
ref["objects"] = [ref["objects"][0]]
for i, v in enumerate(levels):
    rgb = colorsys.hsv_to_rgb((1-v/255) % 1, 1, v/255)
    color = "#"+"".join(f"{round(c*255):02X}" for c in rgb)
    ref["objects"].append(obj("Reference bar", "shape", x=i*20, width=20, color=color))
file = out / "spectrum-reference.orrp"
file.write_text(json.dumps(ref, indent=2))
reference = out / "spectrum-reference.png"
run(exe, "snapshot", file, "--time", 1.3, "--out", reference)
a, b = raw(image), raw(reference)
assert sum(abs(x-y) for x, y in zip(a, b))/len(a) < 0.5, "Spectrum differs from independent hue-wheel reference"
print("Picture-effect acceptance passed: key-before-adjustment/tint, alpha compositing, source/display agreement, timed key removal, encoded nonzero range and independent spectrum reference.")
print(out / "effects-1.3.png")
