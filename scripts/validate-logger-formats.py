#!/usr/bin/env python3
"""MSL units and saved second-session selection against independent CSV pixels/media."""
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/logger-formats/acceptance'
out.mkdir(parents=True,exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    r = subprocess.run(list(map(str,args)),capture_output=True)
    if r.returncode: raise RuntimeError(r.stderr.decode(errors='replace'))
    return r.stdout


def pixels(file): return run('ffmpeg','-v','error','-i',file,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')


msl = out/'original.msl'
lines = ['Original synthetic ECU log','Time\tRPM\tTPS\tCLT\tVSS1','ms\tRPM\t%\tF\tmph']
for session in range(2):
    for i in range(13):
        lines.append(f'{i*500}\t{1000+session*2000+i*100}\t{i*5}\t{140+i*1.8}\t{10+session*20+i}')
msl.write_text('\n'.join(lines)+'\n')
info = json.loads(run(exe,'inspect-data',msl,'--session',2,'--time',2))
assert len(info['sessions']) == 2 and info['duration'] == 6
assert info['values']['RPM'] == 3400
assert abs(info['values']['Coolant temperature (C)']-64) < 1e-8
csv = out/'reference.csv'
csv.write_text('Time,RPM,Throttle (%),Coolant temperature (C),Speed (mph)\n'+''.join(f'{i/2},{3000+i*100},{i*5},{60+i},{30+i}\n' for i in range(13)))
input_id = str(uuid.uuid4())
source = dict(id=input_id,name='ECU session 2',path=str(msl),kind='data',legacyIndex=0,duration=6,offset=0,volume=1,dataSession=2)
objects = []
for name,kind,channel,x in [('Speed','speed','',0),('RPM','rpm','',34),('Coolant','temperature','coolant',68)]:
    objects.append(dict(id=str(uuid.uuid4()),name=name,kind=kind,style='',inputIndex=0,x=x,y=5,width=30,height=80,opacity=1,visible=True,channel=channel,text='',color='#FFFFFF',minimum=0,maximum=100,start=0,end=1000000,parentIndex=-1))
p = dict(formatVersion=1,name='Original logger fixture',width=480,height=180,fps=10,explicitDuration=6,rangeStart=1,rangeEnd=5,speedUnit='mph',warnings=[],inputs=[source],objects=objects)
project = out/'msl.orrp';project.write_text(json.dumps(p))
reference = copy.deepcopy(p);reference['inputs'][0].pop('dataSession');reference['inputs'][0]['path'] = str(csv)
ref = out/'reference.orrp';ref.write_text(json.dumps(reference))
for time in (0,2,4.5):
    a = out/f'msl-{time}.png';b = out/f'csv-{time}.png'
    run(exe,'snapshot',project,'--time',time,'--out',a);run(exe,'snapshot',ref,'--time',time,'--out',b)
    assert pixels(a) == pixels(b),time
full = out/'full.mp4';chunk = out/'chunk.mp4'
full.unlink(missing_ok=True);chunk.unlink(missing_ok=True)
run(exe,'export',project,'--out',full);run(exe,'export',project,'--start',2,'--duration',0.5,'--out',chunk)
for file,t,name in ((full,1,'full'),(chunk,0,'chunk')):
    run('ffmpeg','-v','error','-y','-i',file,'-ss',t,'-frames:v',1,out/f'{name}.png')
a = pixels(out/'full.png');b = pixels(out/'chunk.png')
assert sum(abs(x-y) for x,y in zip(a,b))/len(a) < 2
# Independent GUTMA fixture: explicit units, timezone anchor, and a missing GPS/speed row.
gutma = out/'flight.json'
gutma.write_text(json.dumps(dict(exchange=dict(exchange_type='flight_logging',message=dict(flight_logging=dict(
    flight_logging_keys=['timestamp','gps_lon','gps_lat','speed','battery_voltage'],
    flight_logging_items=[[0.5,20,10,3,12],[1,None,None,None,11],[1.5,21,11,4,10]],
    logging_start_dtg='2026-01-01T00:00:00.000Z',uom_system='Metric'))))))
gap = json.loads(run(exe,'inspect-data',gutma,'--time',0.5))
assert gap['values']['Latitude (deg)'] is None and gap['values']['Speed (m/s)'] is None
assert gap['firstSampleUnixTime'] == 1767225600.5
invalid = subprocess.run([str(exe),'inspect-data',str(msl),'--session','3'],capture_output=True)
assert invalid.returncode and b'data sessions' in invalid.stderr
print('Logger formats: MSL units/second-session CLI, independent CSV pixels, marked full/chunk video, GUTMA UTC/gaps and invalid selection passed')
