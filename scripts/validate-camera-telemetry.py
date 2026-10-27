#!/usr/bin/env python3
"""Original GoPro-style packets plus independent CSV reference, linked rate/loop and encoded ranges."""
import copy
import json
import struct
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/camera-telemetry/acceptance'
out.mkdir(parents=True, exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    result = subprocess.run(list(map(str,args)),capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


def pixels(file):
    return run('ffmpeg','-v','error','-i',file,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')


def difference(a,b):
    assert len(a) == len(b)
    return sum(abs(x-y) for x,y in zip(a,b))/len(a)


u = lambda v: struct.pack('>I',v)

def atom(k,d): return u(len(d)+8)+k.encode()+d

def klv(k,t,w,n,d): return k.encode()+bytes([t,w])+struct.pack('>H',n)+d+b'\0'*((-len(d)) % 4)

def boxes(data):
    p = 0
    while p < len(data):
        n = int.from_bytes(data[p:p+4],'big')
        assert n >= 8
        yield data[p+4:p+8],data[p+8:p+n]
        p += n


base = out/'source.mp4'
run('ffmpeg','-v','error','-y','-f','lavfi','-i','color=c=0x263342:s=320x180:r=10:d=8','-an','-c:v','libx264',base)
parts = list(boxes(base.read_bytes()))
movie = next(body for kind,body in parts if kind == b'moov')
prefix = b''.join(atom(kind.decode(),body) for kind,body in parts if kind != b'moov')
packets = []
for second in range(8):
    values = []
    for t in (second,second+0.5): values += [int(100+200*t),200,300]
    stream = klv('SCAL',108,4,1,u(100))+klv('ACCL',115,6,2,struct.pack('>6h',*values))
    device = klv('STRM',0,1,len(stream),stream)
    packets.append(klv('DEVC',0,1,len(device),device))
clock = b'\0'*12+u(1000)+u(8000)+b'\0'*4
stsd = atom('stsd',u(0)+u(1)+atom('gpmd',b'\0'*6+b'\0\1'))
stsz = atom('stsz',u(0)+u(0)+u(8)+b''.join(u(len(p)) for p in packets))
stco = atom('stco',u(0)+u(1)+u(len(prefix)+8))
stsc = atom('stsc',u(0)+u(1)+u(1)+u(8)+u(1))
stts = atom('stts',u(0)+u(1)+u(8)+u(1000))
dinf = atom('dinf',atom('dref',u(0)+u(1)+atom('url ',u(1))))
matrix = b''.join(u(v) for v in [65536,0,0,0,65536,0,0,0,1073741824])
tkhd = u(3)+u(0)+u(0)+u(2)+u(0)+u(8000)+b'\0'*16+matrix+b'\0'*8
handler = u(0)+u(0)+b'meta'+b'\0'*12+b'GoPro telemetry\0'
metadata = atom('trak',atom('tkhd',tkhd)+atom('mdia',atom('mdhd',clock)+atom('hdlr',handler)+atom('minf',atom('nmhd',u(0))+dinf+atom('stbl',stsd+stsz+stco+stsc+stts))))
# Existing video chunks keep their absolute offsets; only the trailing movie index moves.
movie = b''.join(atom(kind.decode(),body[:-4]+u(3) if kind == b'mvhd' else body) for kind,body in boxes(movie))
camera = out/'camera.mp4';camera.write_bytes(prefix+atom('mdat',b''.join(packets))+atom('moov',movie+metadata))
info = json.loads(run(exe,'inspect-data',camera,'--time','2.25'))
assert abs(info['values']['Camera acceleration axis 1 (m/s²)']-5.5) < 1e-8
assert info['duration'] == 8
csv = out/'reference.csv'
csv.write_text('Time,Camera acceleration axis 1 (m/s²)\n'+''.join(f'{i/2},{1.25+i}\n' for i in range(17)))
video_id = str(uuid.uuid4());data_id = str(uuid.uuid4())
timing = dict(trimStart=1,trimEnd=7,projectStart=0.5,rate=2,loop=True)
video = dict(id=video_id,name='Camera',path=str(camera),kind='video',offset=0,duration=8,volume=1,legacyIndex=0,timing=timing)
data = dict(id=data_id,name='Camera data',path=str(camera),kind='data',offset=0.125,duration=8,volume=1,legacyIndex=1,cameraVideoID=video_id)
def display(name,kind,index):
    return dict(id=str(uuid.uuid4()),name=name,kind=kind,style='',inputIndex=index,x=0,y=0,width=100,height=100,opacity=1,visible=True,channel='',text='',color='#FFFFFF',minimum=0,maximum=20,start=0,end=1000000,parentIndex=-1)
v = display('Camera','video',0);g = display('Camera acceleration','gauge',1)
g.update(x=5,y=5,width=40,height=50,channel='Camera acceleration axis 1 (m/s²)')
p = dict(formatVersion=1,name='Original camera extraction',width=320,height=180,fps=10,explicitDuration=6.5,rangeStart=1,rangeEnd=6,speedUnit='m/s',warnings=[],inputs=[video,data],objects=[v,g])
source = out/'camera.orrp';source.write_text(json.dumps(p))
reference = copy.deepcopy(p);reference['inputs'][1].pop('cameraVideoID');reference['inputs'][1]['path'] = str(csv)
reference['inputs'][1]['timing'] = timing
reference['inputs'][1]['offset'] = 0  # Residual sync shifts values, never the camera loop period.
ref = out/'reference.orrp';ref.write_text(json.dumps(reference))
for t in (1.1,3.4,3.6,5.9):
    a = out/f'camera-{t}.png';b = out/f'csv-{t}.png'
    run(exe,'snapshot',source,'--time',t,'--out',a)
    run(exe,'snapshot',ref,'--time',t,'--out',b)
    assert pixels(a) == pixels(b), (t,difference(pixels(a),pixels(b)))
full = out/'full.mp4';chunk = out/'chunk.mp4'
full.unlink(missing_ok=True);chunk.unlink(missing_ok=True)
run(exe,'export',source,'--out',full)
run(exe,'export',source,'--start',3.6,'--duration',0.5,'--out',chunk)
for file,t,name in ((full,2.6,'full'),(chunk,0,'chunk')):
    run('ffmpeg','-v','error','-y','-i',file,'-ss',t,'-frames:v',1,out/f'{name}.png')
a = pixels(out/'full.png');b = pixels(out/'chunk.png')
assert difference(a,b) < 2, difference(a,b)
assert difference(b,pixels(out/'camera-3.6.png')) < 4, difference(b,pixels(out/'camera-3.6.png'))
print('Camera extraction: scaled samples, independent CSV pixels, linked trim/rate/loop, marked full render and nonzero chunk passed')
