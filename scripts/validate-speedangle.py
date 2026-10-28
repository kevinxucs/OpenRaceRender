#!/usr/bin/env python3
"""Original SA/CSV media comparison and optional public SA/VBO source comparison."""
import argparse
import copy
import json
import plistlib
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/speedangle/acceptance'
out.mkdir(parents=True,exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--public-reference',type=Path)
parser.add_argument('--public-vbo',type=Path)
args = parser.parse_args()


def run(*command):
    result = subprocess.run(list(map(str,command)),capture_output=True)
    if result.returncode: raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


def pixels(file): return run('ffmpeg','-v','error','-i',file,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')


lines = ['; Original synthetic SpeedAngle fixture','#V=4.0.0=','#D=01-01-2026 12:00:00=','#S=Original track=','<trackplan #sectors=2>','</trackplan>','<timer #unit=KM/h>','#2,0:01.250','#2,0:03.750','</timer>','<trace #pt=50>']
reference = ['Time,Latitude (deg),Longitude (deg),Speed (km/h),Lean angle (deg),SA acceleration (raw)']
for i in range(51):
    valid = i != 22
    lines.append(f'10.{100000+i},20.{100000+i},{i-10},{i-9},25,26,{36+i},-255,10,{int(valid)},{"F" if i in [12,37] else "0"}')
    reference.append(f'{i/10},{10.1+i/1000000 if valid else "nan"},{20.1+i/1000000 if valid else "nan"},{36+i if valid else "nan"},{i-10},25')
sa = out/'original.sa';sa.write_text('\n'.join(lines+['</trace>']))
csv = out/'reference.csv';csv.write_text('\n'.join(reference))
info = json.loads(run(exe,'inspect-data',sa,'--time',2.2))
assert info['samples'] == 51 and info['duration'] == 5 and info['laps'] == 3
assert info['values']['Speed (km/h)'] is None and info['values']['Lean angle (deg)'] == 12
assert 'firstSampleUnixTime' not in info
objects = []
for name,kind,channel,x in [('Speed','speed','',0),('Lean','gauge','Lean angle (deg)',34),('Raw sensor','gauge','SA acceleration (raw)',68)]:
    objects.append(dict(id=str(uuid.uuid4()),name=name,kind=kind,style='',inputIndex=0,x=x,y=5,width=30,height=80,opacity=1,visible=True,channel=channel,text='',color='#FFFFFF',minimum=0,maximum=100,start=0,end=1000000,parentIndex=-1))
source = dict(id=str(uuid.uuid4()),name='Original SA',path=str(sa),kind='data',legacyIndex=0,duration=5,offset=0,volume=1)
p = dict(formatVersion=1,name='Original SpeedAngle fixture',width=480,height=180,fps=10,explicitDuration=5,rangeStart=1,rangeEnd=4,speedUnit='km/h',warnings=[],inputs=[source],objects=objects)
project = out/'sa.orrp';project.write_text(json.dumps(p))
r = copy.deepcopy(p);r['inputs'][0]['path'] = str(csv)
ref = out/'reference.orrp';ref.write_text(json.dumps(r))
for time in [0,1.5,2.2,4]:
    a,b = out/f'sa-{time}.png',out/f'csv-{time}.png'
    run(exe,'snapshot',project,'--time',time,'--out',a);run(exe,'snapshot',ref,'--time',time,'--out',b)
    assert pixels(a) == pixels(b),time
full,chunk = out/'full.mp4',out/'chunk.mp4'
full.unlink(missing_ok=True);chunk.unlink(missing_ok=True)
run(exe,'export',project,'--out',full);run(exe,'export',project,'--start',2,'--duration',1,'--out',chunk)
for file,time,name in [(full,1,'full'),(chunk,0,'chunk')]:run('ffmpeg','-v','error','-y','-i',file,'-ss',time,'-frames:v',1,out/(name+'.png'))
a,b = pixels(out/'full.png'),pixels(out/'chunk.png')
assert sum(abs(x-y) for x,y in zip(a,b))/len(a) < 2
with (root/'build/OpenRaceRender.app/Contents/Info.plist').open('rb') as file: bundle = plistlib.load(file)
assert any('sa' in entry.get('CFBundleTypeExtensions',[]) for entry in bundle['CFBundleDocumentTypes'])
if args.public_reference:
    text = args.public_reference.read_text().splitlines()
    start = next(i for i,line in enumerate(text) if line.startswith('<trace'))
    rows = [line.split(',') for line in text[start+1:] if line and not line.startswith('</')]
    vbo_duration = json.loads(run(exe,'inspect-data',args.public_vbo,'--time',0))['duration'] if args.public_vbo else None
    for i in [0,len(rows)//2,len(rows)-1]:
        report = json.loads(run(exe,'inspect-data',args.public_reference,'--time',i/10))
        assert report['samples'] == len(rows)
        assert abs(report['values']['Latitude (deg)']-float(rows[i][0])) < 1e-8
        assert abs(report['values']['Longitude (deg)']-float(rows[i][1])) < 1e-8
        assert report['values']['Speed (mph)'] == float(rows[i][6])
        if args.public_vbo:
            # Time-of-day subtraction introduces sub-picosecond endpoint rounding.
            vbo = json.loads(run(exe,'inspect-data',args.public_vbo,'--time',min(i/10,vbo_duration)))
            # This public VBO preserves the SA's mph numbers while declaring km/h.
            # Check the actual source values, never use its mislabeled units as truth.
            assert vbo['values']['Speed (km/h)'] == report['values']['Speed (mph)']
            assert vbo['values']['lean-angle'] == report['values']['Lean angle (deg)']
            assert abs(vbo['values']['Latitude']-report['values']['Latitude (deg)']) < 1e-7
            assert abs(vbo['values']['Longitude']-report['values']['Longitude (deg)']) < 1e-7
    print(f'Public reference: {len(rows)} rows retained; raw SA GPS/speed agree. Public VBO GPS/lean agree; its speed numbers are mph despite a km/h header. No reference data is bundled.')
print('SpeedAngle workflow passed: units, invalid-fix clock, independent CSV speed/lean/raw-sensor pixels, marked full/chunk output and Finder registration.')
