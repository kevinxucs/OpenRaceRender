#!/usr/bin/env python3
"""Real DrawTime pixels, location/input metadata and overall/current/previous lap records."""
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/script-semantics/acceptance'
out.mkdir(parents=True, exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


csv = out/'laps.csv'
rows = ['Session title,Recorded session', 'Track name,Original Circuit', 'Time,Speed,Lap']
for t in range(61):
    lap = 0 if t < 2 else 1 if t < 14 else 2 if t < 24 else 3 if t < 37 else 4 if t < 45 else 5
    rows.append(f'{t},{t},{lap}')
csv.write_text('\n'.join(rows)+'\n')
o = dict(id=str(uuid.uuid4()), name='Semantic test', kind='enhanced', style='', inputIndex=0,
         x=0, y=0, width=100, height=100, opacity=1, visible=True, channel='Speed', text='',
         color='#5EE0B5', minimum=0, maximum=100, start=0, end=1000000, parentIndex=-1)
p = dict(formatVersion=1, name='Original script semantics', width=320, height=180, fps=10,
         explicitDuration=60, speedUnit='m/s', warnings=[],
         inputs=[dict(id=str(uuid.uuid4()), name='Renamed logger', kind='data', path=str(csv), legacyIndex=0, duration=60, offset=0, volume=1)],
         objects=[o])
initial = out/'initial.orrp'
initial.write_text(json.dumps(p, indent=2))
bg, fg = out/'background.txt', out/'foreground.txt'
bg.write_text('DrawRect(0,0,SizeX,SizeY,Black,Filled); Print(InputName, LocName);')
foreground = '''Print(GetBestLapNum(),GetBestLapTime(),GetCurBestLapNum(),GetCurBestLapTime(),GetPrevBestLapNum(),GetPrevBestLapTime());
DrawText(InputName,8,170,White,18,AlignH_Left);
DrawText(LocName,8,145,White,18,AlignH_Left);
DrawTime(61.234,3,8,115,White,18,AlignH_Left,0);
DrawTime(61.234,2,8,90,White,18,AlignH_Left,1);
DrawTime(1.234,1,8,65,White,18,AlignH_Left,2);
DrawNumber(GetCurBestLapNum(),0,8,35,White,18,AlignH_Left);
DrawNumber(GetPrevBestLapNum(),0,100,35,White,18,AlignH_Left);'''
fg.write_text(foreground)
source = out/'semantics.orrp'
run(exe, 'script-edit', initial, '--background', bg, '--foreground', fg, '--persistent', '--out', source)
for time, current, previous in [(14, (1, 12), (0, 0)), (25, (2, 10), (1, 12)), (38, (2, 10), (2, 10)), (46, (4, 8), (2, 10))]:
    report = json.loads(run(exe, 'script-check', source, '--time', time))
    assert report['messages'][0] == 'Renamed logger Original Circuit'
    values = [float(x) for x in report['messages'][1].split()]
    assert values == [4, 8, *current, *previous], (time, values)
# Low-resolution full-session and nonzero chunk preserve record and text behavior.
video, chunk = out/f'full-{uuid.uuid4().hex[:8]}.mp4', out/f'chunk-{uuid.uuid4().hex[:8]}.mp4'
run(exe, 'export', source, '--out', video)
run(exe, 'export', source, '--start', '25', '--duration', '1', '--out', chunk)
meta = json.loads(run('ffprobe', '-v', 'error', '-show_format', '-of', 'json', video))
assert abs(float(meta['format']['duration'])-60) < 0.1


def raw(file, time=None):
    args = ['ffmpeg', '-v', 'error']
    if time is not None:
        args += ['-ss', str(time)]
    return run(*args, '-i', file, '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-')


for time, current, previous in [(25, 2, 1), (46, 4, 2)]:
    reference_fg = foreground.replace('DrawText(InputName,', 'DrawText("Renamed logger",').replace('DrawText(LocName,', 'DrawText("Original Circuit",')
    reference_fg = reference_fg.replace('DrawTime(61.234,3,8,115,White,18,AlignH_Left,0);', 'DrawText("00:01:01.234",8,115,White,18,AlignH_Left);')
    reference_fg = reference_fg.replace('DrawTime(61.234,2,8,90,White,18,AlignH_Left,1);', 'DrawText("01:01.23",8,90,White,18,AlignH_Left);')
    reference_fg = reference_fg.replace('DrawTime(1.234,1,8,65,White,18,AlignH_Left,2);', 'DrawText("1.2",8,65,White,18,AlignH_Left);')
    reference_fg = reference_fg.replace('DrawNumber(GetCurBestLapNum(),', f'DrawNumber({current},').replace('DrawNumber(GetPrevBestLapNum(),', f'DrawNumber({previous},')
    ref_text = out/'reference.txt'
    ref_text.write_text(reference_fg)
    ref_project = out/f'reference-{time}.orrp'
    run(exe, 'script-edit', source, '--foreground', ref_text, '--out', ref_project)
    image = out/f'reference-{time}.png'
    run(exe, 'snapshot', ref_project, '--time', time, '--out', image)
    actual, expected = raw(video, time), raw(image)
    assert len(actual) == len(expected) == 320*180*3
    error = sum(abs(a-b) for a, b in zip(actual, expected))/len(actual)
    assert error < 2, (time, error)
full_frame, part = raw(video, 25), raw(chunk)
assert sum(abs(a-b) for a, b in zip(full_frame, part))/len(part) < 1
# Explicit location is independent of the recorded session title and source label.
override = json.loads(source.read_text())
override['inputs'][0]['path'] = str(csv)
override['inputs'][0]['dataSettings'] = dict(assignments={}, fields=[], locationName='Override Circuit')
file = out/'override.orrp'
file.write_text(json.dumps(override))
report = json.loads(run(exe, 'script-check', file, '--time', '25'))
assert report['messages'][0] == 'Renamed logger Override Circuit'
print('Script semantics acceptance passed: actual time text versus literal references, location/input names, distinct overall/current/previous lap records at boundaries, override metadata, low-resolution 60s session and nonzero chunk equivalence.')
print(out/'reference-25.png')
