#!/usr/bin/env python3
"""Camera-free telemetry/still/graphics/audio and blank clips: full, marks and chunks."""
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/camera-free/acceptance'
out.mkdir(parents=True, exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


csv = out/'data.csv'
csv.write_text('Time,Speed\n'+''.join(f'{i/10},{i}\n' for i in range(41)))
ppm = out/'art.ppm'
ppm.write_bytes(b'P6\n32 32\n255\n'+bytes([255,180,20])*32*32)
run('ffmpeg', '-v', 'error', '-y', '-i', ppm, out/'art.png')
run('ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'sine=frequency=660:sample_rate=44100:duration=4', out/'tone.wav')


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style='', inputIndex=-1,
                 x=0, y=0, width=100, height=100, opacity=1, visible=True, channel='', text='',
                 color='#5EE0B5', minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


p = dict(formatVersion=1, name='Camera-free original acceptance', width=320, height=180, fps=30,
         explicitDuration=4, speedUnit='m/s', warnings=[], rangeStart=0.5, rangeEnd=3.5,
         inputs=[dict(id=str(uuid.uuid4()), name=name, path=str(out/file), kind=kind, legacyIndex=i, duration=duration, offset=0, volume=1)
                 for i, (name, file, kind, duration) in enumerate([('Logger', 'data.csv', 'data', 4), ('Sound', 'tone.wav', 'audio', 4), ('Artwork', 'art.png', 'image', 0)])],
         objects=[obj('Background', 'shape', color='#123040', segments=[dict(id=str(uuid.uuid4()), time=2, color='#402030')]),
                  obj('Speed', 'speed', inputIndex=0, x=3, y=10, width=38, height=70),
                  obj('Artwork', 'image', inputIndex=2, text=str(out/'art.png'), x=70, y=60, width=20, height=30),
                  obj('Caption', 'text', text='NO CAMERA', x=45, y=10, width=50, height=18),
                  obj('Audio', 'audio', inputIndex=1)])
source = out/'camera-free.orrp'
source.write_text(json.dumps(p, indent=2))
full = out/f'full-{uuid.uuid4().hex[:8]}.mp4'
chunk = out/f'chunk-{uuid.uuid4().hex[:8]}.mp4'
run(exe, 'export', source, '--out', full)
run(exe, 'export', source, '--start', '2.3', '--duration', '0.5', '--out', chunk)
meta = json.loads(run('ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', full))
v = next(s for s in meta['streams'] if s['codec_type'] == 'video')
a = next(s for s in meta['streams'] if s['codec_type'] == 'audio')
assert (v['width'], v['height'], v['r_frame_rate']) == (320, 180, '30/1')
assert abs(float(meta['format']['duration'])-3) < 0.05 and a['channels'] == 2


def raw(file, time=None):
    args = ['ffmpeg', '-v', 'error']
    if time is not None:
        args += ['-ss', str(time)]
    return run(*args, '-i', file, '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-')


snapshots = []
for time in [0.5, 1.3, 2.3, 3.3]:
    image = out/f'frame-{time}.png'
    run(exe, 'snapshot', source, '--time', time, '--out', image)
    expected = raw(image)
    actual = raw(full, time-0.5)
    assert len(actual) == len(expected) == 320*180*3
    error = sum(abs(a-b) for a, b in zip(actual, expected))/len(actual)
    assert error < 3, (time, error)
    snapshots.append(expected)
assert snapshots[0] != snapshots[1] and snapshots[1] != snapshots[2], 'Telemetry or timeline froze'
part, same = raw(chunk), raw(full, 1.8)
assert sum(abs(a-b) for a, b in zip(part, same))/len(same) < 2, 'Chunk restarted the clock'
# Audio is present and advances normally despite no source video.
audio = run('ffmpeg', '-v', 'error', '-i', full, '-vn', '-f', 'f32le', '-ac', '1', '-')
import struct
samples = struct.unpack('<'+'f'*(len(audio)//4), audio)
assert max(abs(x) for x in samples) > 0.05
# Empty canvas and source-free graphics work with no fake dependency in the file.
blank = copy.deepcopy(p)
blank.update(inputs=[], objects=[], explicitDuration=1, rangeStart=0, rangeEnd=1)
file = out/'blank.orrp'
file.write_text(json.dumps(blank))
video = out/f'blank-{uuid.uuid4().hex[:8]}.mp4'
run(exe, 'export', file, '--out', video)
assert max(raw(video)) < 3
assert json.loads(file.read_text())['inputs'] == []
# A source falsely declared to be a camera must fail, rather than become black.
bad = copy.deepcopy(p)
bad['inputs'] = [dict(id=str(uuid.uuid4()), name='Misdeclared camera', kind='video', path=str(out/'tone.wav'), legacyIndex=0, duration=4, offset=0, volume=1)]
bad['objects'] = [obj('Camera', 'video', inputIndex=0)]
file = out/'bad-camera.orrp'
file.write_text(json.dumps(bad))
invalid = out/'bad-camera.mp4'
result = subprocess.run([str(exe), 'export', str(file), '--out', str(invalid)], capture_output=True)
assert result.returncode != 0 and not invalid.exists() and b'no readable video track' in result.stderr
print('Camera-free acceptance passed: telemetry/still/text/shape/audio, continuous marked/full/chunk frames, audible audio, blank no-input output, dependency-free projects and invalid-camera refusal.')
print(out/'frame-2.3.png')
