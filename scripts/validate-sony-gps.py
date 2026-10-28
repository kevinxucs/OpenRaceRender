#!/usr/bin/env python3
"""Original Sony GPS blocks vs CSV pixels; optionally validate a public sectioned LOG."""
import argparse
import copy
import datetime
import functools
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/sony-gps/acceptance'
out.mkdir(parents=True,exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--public-reference',type=Path)
args = parser.parse_args()


def run(*args):
    result = subprocess.run(list(map(str,args)),capture_output=True)
    if result.returncode: raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


def pixels(file): return run('ffmpeg','-v','error','-i',file,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')


def checked(line): return line+'*'+f'{functools.reduce(int.__xor__,line[1:].encode(),0):02X}'


sections = []
reference = ['Time,Latitude (deg),Longitude (deg),Speed (m/s),GPS heading (deg)']
for j in range(2):
    lines = [f'@Sonygps/ver5.0/wgs-84/20260101{12+j}0000.000/']
    for i in range(51):
        valid = i != 22
        speed = 10+j*40+i/10
        lines += [checked(f'$GPRMC,{12+j}00{i//10:02}.{i%10}00,{"A" if valid else "V"},1000,N,02000,E,{speed},90,010126,,,A')]
        if j == 1: reference += [f'{i/10},{10 if valid else "nan"},{20 if valid else "nan"},{speed*0.514444 if valid else "nan"},{90 if valid else "nan"}']
    sections += ['\n'.join(lines)+'\n']
moff = out/'original.moff';moff.write_bytes(b'MOFF8Original synthetic index\0\xff'+b'\0\xff'.join(s.encode() for s in sections))
csv = out/'reference.csv';csv.write_text('\n'.join(reference))
info = json.loads(run(exe,'inspect-data',moff,'--session',2,'--time',2.2))
assert len(info['sessions']) == 2 and info['samples'] == 51 and info['duration'] == 5
assert info['values']['Speed (m/s)'] is None and info['firstSampleUnixTime'] == 1767272400
objects = []
for i,(kind,channel) in enumerate([('speed',''),('gauge','GPS heading (deg)')]):
    objects.append(dict(id=str(uuid.uuid4()),name=channel or 'Speed',kind=kind,style='',inputIndex=0,x=i*50,y=5,width=45,height=80,opacity=1,visible=True,channel=channel,text='',color='#FFFFFF',minimum=0,maximum=200,start=0,end=1000000,parentIndex=-1))
p = dict(formatVersion=1,name='Original Sony GPS workflow',width=480,height=180,fps=10,explicitDuration=5,rangeStart=1,rangeEnd=4,speedUnit='km/h',warnings=[],inputs=[dict(id=str(uuid.uuid4()),name='Sony GPS',path=str(moff),kind='data',legacyIndex=0,duration=5,offset=0,volume=1,dataSession=2)],objects=objects)
project = out/'sony.orrp';project.write_text(json.dumps(p))
r = copy.deepcopy(p);r['inputs'][0]['path'] = str(csv);r['inputs'][0].pop('dataSession')
ref = out/'reference.orrp';ref.write_text(json.dumps(r))
for time in [0,1.5,2.2,4]:
    a,b = out/f'sony-{time}.png',out/f'csv-{time}.png'
    run(exe,'snapshot',project,'--time',time,'--out',a);run(exe,'snapshot',ref,'--time',time,'--out',b)
    assert pixels(a) == pixels(b),time
full,chunk = out/'full.mp4',out/'chunk.mp4'
full.unlink(missing_ok=True);chunk.unlink(missing_ok=True)
run(exe,'export',project,'--out',full);run(exe,'export',project,'--start',2,'--duration',0.5,'--out',chunk)
for file,time,name in [(full,1,'full'),(chunk,0,'chunk')]:run('ffmpeg','-v','error','-y','-i',file,'-ss',time,'-frames:v',1,out/(name+'.png'))
a,b = pixels(out/'full.png'),pixels(out/'chunk.png')
assert sum(abs(x-y) for x,y in zip(a,b))/len(a) < 2
if args.public_reference:
    blocks = args.public_reference.read_text().split('@Sonygps/ver')[1:]
    for index,block in enumerate(blocks,1):
        rows = [line.split('*')[0].split(',') for line in block.splitlines() if line.startswith(('$GPRMC,','$GNRMC,'))]
        first = rows[0]
        date = first[9]
        clock = first[1]
        epoch = datetime.datetime(2000+int(date[4:6]),int(date[2:4]),int(date[:2]),int(clock[:2]),int(clock[2:4]),int(float(clock[4:])),tzinfo=datetime.timezone.utc).timestamp()+float(clock[4:])%1
        info = json.loads(run(exe,'inspect-data',args.public_reference,'--session',index,'--time',0))
        assert info['samples'] == len(rows) and abs(info['firstSampleUnixTime']-epoch) < 1e-6
        assert abs(info['values']['Speed (m/s)']-float(first[7])*0.514444) < 1e-8
    print(f'Public anonymized LOG: {len(blocks)} separate recordings; dated RMC counts, UTC and speed agree. This is a LOG reference, not a real binary MOFF container validation.')
print('Sony GPS passed: independent CSV pixels, second-recording selection, void-fix clock and marked full/chunk video. MOFF fixture framing is synthetic.')
