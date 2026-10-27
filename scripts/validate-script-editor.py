#!/usr/bin/env python3
"""Author original source via public CLI, test diagnostics, persist, render full/chunk."""
import base64
import copy
import hashlib
import json
import struct
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/script-editor/acceptance'
out.mkdir(parents=True, exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


def obj(name, kind, **kw):
    value = dict(id=str(uuid.uuid4()), name=name, kind=kind, style='', inputIndex=-1,
                 x=0, y=0, width=100, height=100, opacity=1, visible=True, channel='', text='',
                 color='#5EE0B5', minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
    value.update(kw)
    return value


csv = out/'data.csv'
csv.write_text('Time,Speed\n'+''.join(f'{i/10},{i}\n' for i in range(41)))
p = dict(formatVersion=1, name='Original script editor acceptance', width=320, height=180, fps=30,
         explicitDuration=4, speedUnit='m/s', warnings=[], rangeStart=0, rangeEnd=4,
         inputs=[dict(id=str(uuid.uuid4()), name='Logger', kind='data', path=str(csv), legacyIndex=0, duration=4, offset=0, volume=1)],
         objects=[obj('Original enhanced display', 'enhanced', inputIndex=0, channel='Speed')])
source = out/'initial.orrp'
source.write_text(json.dumps(p, indent=2))
initial_hash = hashlib.sha256(source.read_bytes()).digest()
bg, fg = out/'background.txt', out/'foreground.txt'
bg.write_text('Print("background"); count=0; DrawRect(0,0,SizeX,SizeY,Red,Filled);')
fg.write_text('count += 1; Print("frame", count, DisplayTime); if (DataValue >= 20) DrawRect(0,0,SizeX,SizeY,Blue,Filled);')
authored = out/'authored.orrp'
run(exe, 'script-edit', source, '--object', '0', '--background', bg, '--foreground', fg,
    '--canvas-width', '320', '--canvas-height', '180', '--font', 'Helvetica', '--persistent', '--out', authored)
assert hashlib.sha256(source.read_bytes()).digest() == initial_hash
project = json.loads(authored.read_text())
assert uuid.UUID(project['objects'][0]['id']) == uuid.UUID(p['objects'][0]['id'])
assert len(project['inputs']) == len(p['inputs'])
for actual, expected in zip(project['inputs'], p['inputs']):
    assert uuid.UUID(actual['id']) == uuid.UUID(expected['id'])
    assert {k: v for k, v in actual.items() if k not in ['id', 'path']} == {k: v for k, v in expected.items() if k not in ['id', 'path']}
    assert (authored.parent / actual['path']).resolve() == Path(expected['path']).resolve()
payload = base64.b64decode(project['objects'][0]['legacyPayload'])
assert payload[1632:1632+len(bg.read_bytes())] == bg.read_bytes()
assert payload[34400:34400+len(fg.read_bytes())] == fg.read_bytes()
assert struct.unpack_from('<HH', payload, 280) == (320, 180)
report = json.loads(run(exe, 'script-check', authored, '--object', '0', '--time', '2.3', '--out', out/'test.png'))
assert report['compiled'] and report['messages'] == ['background', 'frame 70.0 2.3'], report
# This also exercises the API's message sink without historical spam.
video = out/f'scripts-{uuid.uuid4().hex[:8]}.mp4'
chunk = out/f'chunk-{uuid.uuid4().hex[:8]}.mp4'
run(exe, 'export', authored, '--out', video)
run(exe, 'export', authored, '--start', '2.3', '--duration', '0.5', '--out', chunk)


def raw(file, time=None):
    args = ['ffmpeg', '-v', 'error']
    if time is not None:
        args += ['-ss', str(time)]
    return run(*args, '-i', file, '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-')


for time, color in [(1.0, '#FF0000'), (2.3, '#0000FF'), (3.0, '#0000FF')]:
    reference = copy.deepcopy(p)
    reference['objects'] = [obj('Independent expected solid color', 'shape', color=color)]
    file = out/'reference.orrp'
    file.write_text(json.dumps(reference))
    image = out/f'reference-{time}.png'
    run(exe, 'snapshot', file, '--time', time, '--out', image)
    expected, actual = raw(image), raw(video, time)
    assert len(actual) == len(expected) == 320*180*3
    assert sum(abs(a-b) for a, b in zip(actual, expected))/len(actual) < 2
full_frame, part = raw(video, 2.3), raw(chunk)
assert sum(abs(a-b) for a, b in zip(full_frame, part))/len(part) < 1
# Template strips session dependencies while retaining source/settings.
template = out/'script.orrt'
run(exe, 'convert', authored, '--out', template)
assert json.loads(template.read_text())['objects'][0]['legacyPayload'] == project['objects'][0]['legacyPayload']
layout = json.loads(template.read_text())
assert all(not source['path'] and source['duration'] == 0 for source in layout['inputs'])
assert 'rangeStart' not in layout and 'rangeEnd' not in layout
sample_report = json.loads(run(exe, 'script-check', template, '--object', '0', '--time', '2.3', '--samples'))
assert sample_report['compiled'] and sample_report['sampleData']
bad = out/'invalid.txt'
bad.write_text('if (False) { NotAFunction(); }')
invalid = out/'invalid.orrp'
result = subprocess.run([str(exe), 'script-edit', str(source), '--object', '0', '--foreground', str(bad), '--out', str(invalid)], capture_output=True)
assert result.returncode != 0 and not invalid.exists() and b'Unsupported Enhanced function' in result.stderr
print('Script-editor acceptance passed: source import/apply, exact program/settings persistence, current-only Print diagnostics, independent colored frames, telemetry trigger, full/chunk agreement, reusable source and invalid no-output checks.')
print(out/'test.png')
