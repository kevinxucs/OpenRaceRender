#!/usr/bin/env python3
"""Original multi-session FITs, optional Garmin SDK oracle, and rendered CSV equivalence."""
import argparse
import copy
import json
import struct
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/fit-sessions/acceptance'
out.mkdir(parents=True,exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sdk',action='store_true',help='Also compare the original fixture with the installed official garmin-fit-sdk decoder.')
args = parser.parse_args()
origin = 1_000_000_000


def crc(data):
    value = 0
    for byte in data:
        value ^= byte
        for _ in range(8): value = (value >> 1) ^ (0xa001 if value & 1 else 0)
    return value


def definition(local,message,fields):
    return bytes([0x40|local,0,0])+struct.pack('<H',message)+bytes([len(fields)])+bytes(n for f in fields for n in f)


def fixture(first):
    definitions = definition(0,0,[(0,1,0),(1,2,0x84),(4,4,0x86)])
    definitions += definition(1,20,[(253,4,0x86),(6,2,0x84)])
    definitions += definition(2,18,[(253,4,0x86),(2,4,0x86),(7,4,0x86),(8,4,0x86),(254,2,0x84)])
    definitions += definition(3,19,[(253,4,0x86),(2,4,0x86),(7,4,0x86),(8,4,0x86)])
    definitions += definition(4,34,[(253,4,0x86),(0,4,0x86),(1,2,0x84)])
    file_id = bytes([0])+struct.pack('<BHI',4,255,origin)
    summaries = b''.join(bytes([2])+struct.pack('<IIIIH',origin+start,origin+start,2000,2000,index) for index,start in enumerate([0,3]))
    records = b''.join(bytes([1])+struct.pack('<IH',origin+t,speed*1000) for t,speed in enumerate([10,11,12,20,21,22]))
    laps = b''.join(bytes([3])+struct.pack('<IIII',origin+t+1,origin+t,1000,1000) for t in [0,1,3,4])
    activity = bytes([4])+struct.pack('<IIH',origin+5,4000,2)
    body = definitions+file_id+(summaries+laps+records if first else records+laps+summaries)+activity
    header = struct.pack('<BBHI4s',14,0x20,0,len(body),b'.FIT')
    data = header+struct.pack('<H',crc(header))+body
    return data+struct.pack('<H',crc(data))


def run(*command):
    result = subprocess.run(list(map(str,command)),capture_output=True)
    if result.returncode: raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


def pixels(file): return run('ffmpeg','-v','error','-i',file,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')


for first in [False,True]:
    file = out/('summary-first.fit' if first else 'summary-last.fit')
    file.write_bytes(fixture(first))
    info = json.loads(run(exe,'inspect-data',file,'--session',2,'--time',1))
    assert [s['samples'] for s in info['sessions']] == [3,3]
    assert info['duration'] == 2 and info['values']['Speed (m/s)'] == 21
    assert info['firstSampleUnixTime'] == origin+3+631065600
    if args.sdk:
        from garmin_fit_sdk import Decoder, Stream
        messages,errors = Decoder(Stream.from_file(str(file))).read(convert_datetimes_to_dates=False)
        assert not errors,errors
        summaries = messages['session_mesgs']
        assert [s['start_time'] for s in summaries] == [origin,origin+3]
        assert [s['total_elapsed_time'] for s in summaries] == [2,2]
        assert [r['speed'] for r in messages['record_mesgs']] == [10,11,12,20,21,22]

source = dict(id=str(uuid.uuid4()),name='FIT session 2',path=str(out/'summary-first.fit'),kind='data',legacyIndex=0,duration=2,offset=0,volume=1,dataSession=2)
widget = dict(id=str(uuid.uuid4()),name='Speed',kind='speed',style='',inputIndex=0,x=5,y=5,width=90,height=90,opacity=1,visible=True,channel='',text='',color='#FFFFFF',minimum=0,maximum=100,start=0,end=1000000,parentIndex=-1)
project = dict(formatVersion=1,name='Original FIT session fixture',width=320,height=180,fps=10,explicitDuration=2,rangeStart=0.5,rangeEnd=1.5,speedUnit='m/s',warnings=[],inputs=[source],objects=[widget])
path = out/'selected.orrp';path.write_text(json.dumps(project))
reference = copy.deepcopy(project);reference['inputs'][0].pop('dataSession');reference['inputs'][0]['path'] = str(out/'reference.csv')
(out/'reference.csv').write_text('Time,Speed (m/s)\n0,20\n1,21\n2,22\n')
ref = out/'reference.orrp';ref.write_text(json.dumps(reference))
for time in [0,1,1.5]:
    a,b = out/f'fit-{time}.png',out/f'csv-{time}.png'
    run(exe,'snapshot',path,'--time',time,'--out',a);run(exe,'snapshot',ref,'--time',time,'--out',b)
    assert pixels(a) == pixels(b),time
full,chunk = out/'full.mp4',out/'chunk.mp4'
full.unlink(missing_ok=True);chunk.unlink(missing_ok=True)
run(exe,'export',path,'--out',full);run(exe,'export',path,'--start',1,'--duration',0.5,'--out',chunk)
for file,time,name in [(full,0.5,'full'),(chunk,0,'chunk')]:run('ffmpeg','-v','error','-y','-i',file,'-ss',time,'-frames:v',1,out/(name+'.png'))
a,b = pixels(out/'full.png'),pixels(out/'chunk.png')
assert sum(abs(x-y) for x,y in zip(a,b))/len(a) < 2
print('Internal FIT sessions passed: summary ordering, elapsed bounds, UTC, independent CSV pixels and marked full/chunk export'+('; official Garmin SDK values match.' if args.sdk else '.'))
