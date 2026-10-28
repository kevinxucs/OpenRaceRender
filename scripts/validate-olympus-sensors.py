#!/usr/bin/env python3
"""Original sensor packets against independent CSV pixels and marked video."""
import copy
import json
import plistlib
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/olympus-sensors/acceptance'
out.mkdir(parents=True,exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    r = subprocess.run(list(map(str,args)),capture_output=True)
    if r.returncode: raise RuntimeError(r.stderr.decode(errors='replace'))
    return r.stdout


def pixels(file): return run('ffmpeg','-v','error','-i',file,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')


sensor,reference = [],['Time,Ambient temperature (C),Atmospheric pressure (hPa),Camera acceleration X (raw)']
for i in range(21):
    clock = f'1200{i//5:02}.{i%5*2}'
    sensor += [f'$OLTIM,20260101,{clock}',f'$OLTMP,{68+i*1.8},1,0',f'$OLACC,{1000+i},0,0']
    if i != 10: sensor += [f'$OLPRE,{1000+i},100,328.084']
    reference += [f'{i/5},{20+i},{1000+i if i != 10 else "nan"},{1000+i}']
sensor += ['$OLSNSGPSTIM,20260101,120000,20260101,120002']
sa = out/'original.SNS';sa.write_text('\n'.join(sensor))
csv = out/'reference.csv';csv.write_text('\n'.join(reference))
info = json.loads(run(exe,'inspect-data',sa,'--time',2))
assert info['samples'] == 21 and info['duration'] == 4 and info['firstSampleUnixTime'] == 1767268802
assert info['values']['Atmospheric pressure (hPa)'] is None
assert info['values']['Ambient temperature (C)'] == 30
objects = []
for index,(channel,maximum) in enumerate([('Ambient temperature (C)',100),('Atmospheric pressure (hPa)',1200),('Camera acceleration X (raw)',1500)]):
    objects.append(dict(id=str(uuid.uuid4()),name=channel,kind='gauge',style='',inputIndex=0,x=index*34,y=5,width=30,height=80,opacity=1,visible=True,channel=channel,text='',color='#FFFFFF',minimum=0,maximum=maximum,start=0,end=1000000,parentIndex=-1))
p = dict(formatVersion=1,name='Original sensor workflow',width=480,height=180,fps=10,explicitDuration=4,rangeStart=1,rangeEnd=3,speedUnit='km/h',warnings=[],inputs=[dict(id=str(uuid.uuid4()),name='Sensors',path=str(sa),kind='data',legacyIndex=0,duration=4,offset=0,volume=1)],objects=objects)
project = out/'sensors.orrp';project.write_text(json.dumps(p))
r = copy.deepcopy(p);r['inputs'][0]['path'] = str(csv)
ref = out/'reference.orrp';ref.write_text(json.dumps(r))
for time in [0,1.4,2,3.8]:
    a,b = out/f'sensors-{time}.png',out/f'csv-{time}.png'
    run(exe,'snapshot',project,'--time',time,'--out',a);run(exe,'snapshot',ref,'--time',time,'--out',b)
    assert pixels(a) == pixels(b),time
full,chunk = out/'full.mp4',out/'chunk.mp4'
full.unlink(missing_ok=True);chunk.unlink(missing_ok=True)
run(exe,'export',project,'--out',full);run(exe,'export',project,'--start',2,'--duration',0.5,'--out',chunk)
for file,time,name in [(full,1,'full'),(chunk,0,'chunk')]:run('ffmpeg','-v','error','-y','-i',file,'-ss',time,'-frames:v',1,out/(name+'.png'))
a,b = pixels(out/'full.png'),pixels(out/'chunk.png')
assert sum(abs(x-y) for x,y in zip(a,b))/len(a) < 2
with (root/'build/OpenRaceRender.app/Contents/Info.plist').open('rb') as file: bundle = plistlib.load(file)
assert any('sns' in item.get('CFBundleTypeExtensions',[]) for item in bundle['CFBundleDocumentTypes'])
print('Olympus sensors passed: corrected UTC, temperature units, missing packet values, independent CSV pixels, marked full/chunk video and Finder registration.')
