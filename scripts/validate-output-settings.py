#!/usr/bin/env python3
"""Independent output geometry, marked-time frames, AAC formats and CLI profiles."""
import copy
import hashlib
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / 'build/validation/output-settings/acceptance'
out.mkdir(parents=True, exist_ok=True)
exe = root / 'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


run('ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=3',
    '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:duration=3',
    '-f', 'lavfi', '-i', 'sine=frequency=880:sample_rate=48000:duration=3',
    '-filter_complex', '[1:a][2:a]amerge=inputs=2[a]', '-map', '0:v', '-map', '[a]',
    '-c:v', 'libx264', '-crf', '10', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '240k', out/'camera.mp4')


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style='', inputIndex=-1,
                 x=0, y=0, width=100, height=100, opacity=1, visible=True, channel='', text='',
                 color='#FFFFFF', minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


p = dict(formatVersion=1, name='Independent output acceptance', width=640, height=360, fps=30,
         speedUnit='mph', warnings=[], rangeStart=0.5, rangeEnd=1.5,
         inputs=[dict(id=str(uuid.uuid4()), name='Original synthetic camera', kind='video',
                      path=str(out/'camera.mp4'), legacyIndex=0, duration=3, offset=0, volume=1)],
         objects=[obj('Camera', 'video', inputIndex=0),
                  obj('Edge widget', 'shape', x=75, y=75, width=25, height=25)])
original = out/'original.orrp'
original.write_text(json.dumps(p, indent=2))
original_hash = hashlib.sha256(original.read_bytes()).digest()


def info(file):
    return json.loads(run('ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', file))


def raw(file, time=None):
    args = ['ffmpeg', '-v', 'error']
    if time is not None:
        args += ['-ss', str(time)]
    return run(*args, '-i', file, '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-')


for workspace, x, y, w, h in [('fitCanvas', 32, 78, 576, 324), ('output', 32, 24, 576, 432)]:
    project = copy.deepcopy(p)
    output = dict(width=640, height=480, fps=15, workspace=workspace, border=0.05,
                  scaling='high', audioChannels=1, audioSampleRate=44100)
    project['exportSettings'] = dict(videoBitRate=5000000, audioBitRate=128000, output=output)
    source = out/f'{workspace}.orrp'
    source.write_text(json.dumps(project, indent=2))
    video = out/f'{workspace}-{uuid.uuid4().hex[:8]}.mp4'
    run(exe, 'export', source, '--out', video)
    meta = info(video)
    v = next(s for s in meta['streams'] if s['codec_type'] == 'video')
    a = next(s for s in meta['streams'] if s['codec_type'] == 'audio')
    assert (v['width'], v['height'], v['r_frame_rate']) == (640, 480, '15/1')
    assert (a['channels'], a['sample_rate']) == (1, '44100')
    assert abs(float(meta['format']['duration'])-1) < 0.08
    ref = copy.deepcopy(p)
    ref.update(width=640, height=480)
    for widget in ref['objects']:
        widget.update(x=(x+widget['x']/100*w)/640*100, y=(y+widget['y']/100*h)/480*100,
                      width=widget['width']/100*w/640*100, height=widget['height']/100*h/480*100)
    # Reshape the camera only in the output workspace, matching its explicit choice.
    # Its default maintains video aspect, so both independent/reference scenes do too.
    reference = out/f'{workspace}-reference.orrp'
    reference.write_text(json.dumps(ref, indent=2))
    for project_time in [0.5, 0.9, 1.3]:
        image = out/f'{workspace}-{project_time}.png'
        run(exe, 'snapshot', reference, '--time', project_time, '--out', image)
        expected = raw(image)
        actual = raw(video, project_time-0.5)
        assert len(expected) == len(actual) == 640*480*3
        error = sum(abs(a-b) for a, b in zip(actual, expected))/len(actual)
        assert error < 5, (workspace, project_time, error)
        # Border corners are black, including around the vector edge widget.
        assert max(actual[:30]) < 5 and max(actual[-30:]) < 5
    assert json.loads(source.read_text())['width'] == 640 and json.loads(source.read_text())['height'] == 360
    assert json.loads(source.read_text())['fps'] == 30

cli_video = out/f'cli-{uuid.uuid4().hex[:8]}.mp4'
run(exe, 'export', original, '--profile', 'internet-720', '--width', '640', '--height', '480', '--fps', '15',
    '--workspace', 'output', '--border', '5', '--scaling', 'nearest', '--audio-channels', '0', '--out', cli_video)
meta = info(cli_video)
v = next(s for s in meta['streams'] if s['codec_type'] == 'video')
assert (v['width'], v['height'], v['r_frame_rate']) == (640, 480, '15/1')
assert not any(s['codec_type'] == 'audio' for s in meta['streams'])
profile_video = out/f'profile-{uuid.uuid4().hex[:8]}.mp4'
run(exe, 'export', original, '--profile', 'internet-720', '--out', profile_video)
meta = info(profile_video)
v = next(s for s in meta['streams'] if s['codec_type'] == 'video')
a = next(s for s in meta['streams'] if s['codec_type'] == 'audio')
assert (v['width'], v['height'], v['r_frame_rate']) == (1280, 720, '30/1')
assert (a['channels'], a['sample_rate']) == (2, '48000')
assert hashlib.sha256(original.read_bytes()).digest() == original_hash
invalid = out/'invalid.mp4'
result = subprocess.run([str(exe), 'export', str(original), '--width', '641', '--out', str(invalid)], capture_output=True)
assert result.returncode != 0 and not invalid.exists(), 'Odd output dimension was accepted'
print('Output acceptance passed: independently mapped fit/reshape + whole-composition border frames, marked duration, 15 fps, mono 44100 AAC, stereo 48000 profile, disabled audio and CLI overrides with unchanged source canvas/project.')
print(out/'fitCanvas-0.9.png')
