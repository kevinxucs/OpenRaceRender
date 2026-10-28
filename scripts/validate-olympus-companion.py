#!/usr/bin/env python3
"""Paired original SNS/GPSLOG against an independent combined CSV and relocated project."""
import copy
import json
import shutil
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/olympus-companion/acceptance'
out.mkdir(parents=True,exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    result = subprocess.run(list(map(str,args)),capture_output=True)
    if result.returncode: raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


def pixels(file): return run('ffmpeg','-v','error','-i',file,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')


session = out/'original-session'
for folder in ['SNSLOG','GPSLOG']: (session/folder).mkdir(parents=True,exist_ok=True)
sensor = []
for i in range(21):
    sensor += [f'$OLTIM,20260101,1200{i//5:02}.{i%5*2}',f'$OLTMP,{20+i},0,0',f'$OLPRE,{1000+i},100,328.084']
sensor += ['$OLSNSGPSTIM,20260101,120000,20260101,120001']
sns = session/'SNSLOG/26010101.SNS';sns.write_text('\n'.join(sensor))
gps,reference = [],['Time,Latitude (deg),Longitude (deg),Speed (m/s),Ambient temperature (C),Atmospheric pressure (hPa)']
for i in range(31):
    valid = i != 10
    gps += [f'$GPRMC,1200{i//5:02}.{i%5*2},{"A" if valid else "V"},1000.000,N,02000.000,E,{10+i},90,010126,,,A']
    temperature,pressure = (20+i-5,1000+i-5) if 5 <= i <= 25 else ('nan','nan')
    reference += [f'{i/5},{10 if valid else "nan"},{20 if valid else "nan"},{(10+i)*0.514444 if valid else "nan"},{temperature},{pressure}']
log = session/'GPSLOG/26010101.LOG';log.write_text('\n'.join(gps))
csv = out/'combined-reference.csv';csv.write_text('\n'.join(reference))
info = json.loads(run(exe,'inspect-data',sns,'--time',2))
assert info['samples'] == 31 and info['duration'] == 6 and info['firstSampleUnixTime'] == 1767268800
assert info['values']['Speed (m/s)'] is None and info['values']['Ambient temperature (C)'] == 25
objects = []
for i,(kind,channel,maximum) in enumerate([('speed','',100),('gauge','Ambient temperature (C)',100),('gauge','Atmospheric pressure (hPa)',1200)]):
    objects.append(dict(id=str(uuid.uuid4()),name=channel or 'Speed',kind=kind,style='',inputIndex=0,x=i*34,y=5,width=30,height=80,opacity=1,visible=True,channel=channel,text='',color='#FFFFFF',minimum=0,maximum=maximum,start=0,end=1000000,parentIndex=-1))
p = dict(formatVersion=1,name='Original paired workflow',width=480,height=180,fps=10,explicitDuration=6,rangeStart=1,rangeEnd=5,speedUnit='km/h',warnings=[],inputs=[dict(id=str(uuid.uuid4()),name='Paired logs',path='SNSLOG/26010101.SNS',kind='data',legacyIndex=0,duration=6,offset=0,volume=1)],objects=objects)
project = session/'session.orrp';project.write_text(json.dumps(p))
r = copy.deepcopy(p);r['inputs'][0]['path'] = str(csv)
ref = out/'reference.orrp';ref.write_text(json.dumps(r))
for time in [0.8,1.4,2,4.8]:
    a,b = out/f'paired-{time}.png',out/f'csv-{time}.png'
    run(exe,'snapshot',project,'--time',time,'--out',a);run(exe,'snapshot',ref,'--time',time,'--out',b)
    assert pixels(a) == pixels(b),time
moved = out/'relocated-session';shutil.copytree(session,moved,dirs_exist_ok=True)
a,b = out/'paired-1.4.png',out/'relocated.png'
run(exe,'snapshot',moved/'session.orrp','--time',1.4,'--out',b);assert pixels(a) == pixels(b)
full,chunk = out/'full.mp4',out/'chunk.mp4'
full.unlink(missing_ok=True);chunk.unlink(missing_ok=True)
run(exe,'export',project,'--out',full);run(exe,'export',project,'--start',2,'--duration',0.5,'--out',chunk)
for file,time,name in [(full,1,'full'),(chunk,0,'chunk')]:run('ffmpeg','-v','error','-y','-i',file,'-ss',time,'-frames:v',1,out/(name+'.png'))
a,b = pixels(out/'full.png'),pixels(out/'chunk.png')
assert sum(abs(x-y) for x,y in zip(a,b))/len(a) < 2
assert sns.read_text() == '\n'.join(sensor) and log.read_text() == '\n'.join(gps)
print('Olympus companion passed: corrected UTC union, invalid fixes, independent combined CSV pixels, relocated relative project, unchanged originals and marked full/chunk video.')
