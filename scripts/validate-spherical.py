#!/usr/bin/env python3
"""Original panoramic video, analytic fisheye colors, media hashes and full/chunk validation."""
import copy
import json
import math
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/spherical/acceptance'
out.mkdir(parents=True,exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args, data=None):
    r = subprocess.run(list(map(str,args)),input=data,capture_output=True)
    if r.returncode: raise RuntimeError(r.stderr.decode(errors='replace'))
    return r.stdout


def pixels(file): return run('ffmpeg','-v','error','-i',file,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')

def difference(a,b):
    assert len(a) == len(b)
    return sum(abs(x-y) for x,y in zip(a,b))/len(a)


def display(kind):
    return dict(id=str(uuid.uuid4()),name='Original panorama',kind=kind,style='',inputIndex=0,x=-100,y=-100,width=300,height=300,opacity=1,visible=True,channel='',text='',color='#FFFFFF',minimum=0,maximum=100,start=0,end=1000000,parentIndex=-1)


def picture(projection):
    return dict(left=0,right=0,top=0,bottom=0,flipX=False,flipY=False,rotation=0,maintainAspect=True,brightness=1,contrast=1,saturation=1,spherical=projection)


def project(source,kind,width,height):
    return dict(formatVersion=1,name='Original spherical fixture',sphericalWorkspace=True,width=width,height=height,fps=10,explicitDuration=4,rangeStart=1,rangeEnd=3,speedUnit='m/s',warnings=[],inputs=[dict(id=str(uuid.uuid4()),name='Original source',path=str(source),kind=kind,legacyIndex=0,duration=4,offset=0,volume=1)],objects=[display(kind)])


base = out/'panorama.mp4'
pattern = 'color=c=red:s=320x160:r=10:d=4,drawbox=x=80:y=0:w=80:h=160:color=green:t=fill,drawbox=x=160:y=0:w=80:h=160:color=blue:t=fill,drawbox=x=240:y=0:w=80:h=160:color=yellow:t=fill'
encoding = ['-c:v','libx264','-crf','0','-pix_fmt','yuv420p','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709']
run('ffmpeg','-v','error','-y','-f','lavfi','-i',pattern,'-f','lavfi','-i','sine=frequency=440:sample_rate=48000:duration=4',*encoding,'-c:a','aac',base)
reference = out/'shifted.mp4'
run('ffmpeg','-v','error','-y','-i',base,'-filter_complex','[0:v]split[a][b];[a]crop=240:160:80:0[left];[b]crop=80:160:0:0[right];[left][right]hstack[v]','-map','[v]','-an',*encoding,reference)
p = project(base,'video',320,160);p['inputs'][0]['picture'] = picture(dict(mode='equirectangular',pan=90,fieldOfView=240,centerX=0.5,centerY=0.5,radius=0.5,axis='up'))
source = out/'pan.orrp';source.write_text(json.dumps(p))
ref = copy.deepcopy(p);ref.pop('sphericalWorkspace');ref['inputs'][0].pop('picture');ref['inputs'][0]['path'] = str(reference)
ref['objects'][0].update(x=0,y=0,width=100,height=100)
ref_file = out/'reference.orrp';ref_file.write_text(json.dumps(ref))
a = out/'pan.png';b = out/'reference.png'
run(exe,'snapshot',source,'--time',1,'--out',a);run(exe,'snapshot',ref_file,'--time',1,'--out',b)
assert difference(pixels(a),pixels(b)) < 2, difference(pixels(a),pixels(b))
# Tag/clear independent source copies; video and audio packet hashes must not change.
marked = out/'marked.mp4';cleared = out/'cleared.mp4'
marked.unlink(missing_ok=True);cleared.unlink(missing_ok=True)
run(exe,'spherical-metadata',base,'--add','--out',marked)
run(exe,'spherical-metadata',marked,'--clear','--out',cleared)
assert json.loads(run(exe,'spherical-metadata',marked))['sphericalV1']
assert not json.loads(run(exe,'spherical-metadata',cleared))['sphericalV1']
for stream in ['v:0','a:0']:
    digest = lambda f: run('ffmpeg','-v','error','-i',f,'-map','0:'+stream,'-c','copy','-f','hash','-hash','sha256','-')
    assert digest(base) == digest(marked) == digest(cleared)
probe = json.loads(run('ffprobe','-v','error','-show_streams','-of','json',marked))
assert any(d.get('projection') == 'equirectangular' for s in probe['streams'] for d in s.get('side_data_list',[]))
# Original raw gradient image; independent CPU equidistant projection, not the application kernel.
raw = bytes(component for y in range(128) for x in range(128) for component in (x*2,y*2,40))
lens = out/'lens.png';run('ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','128x128','-i','-','-frames:v','1',lens,data=raw)
f = project(lens,'image',256,128);f['objects'][0]['text'] = str(lens)
f['objects'][0]['picture'] = picture(dict(mode='fisheye',pan=0,fieldOfView=240,centerX=0.5,centerY=0.5,radius=0.5,axis='up'))
fisheye = out/'fisheye.orrp';fisheye.write_text(json.dumps(f))
frame = out/'fisheye.png';run(exe,'snapshot',fisheye,'--time',1,'--out',frame)
expected = bytearray()
for row in range(128):
    y = 127-row
    for x in range(256):
        lon=(x+0.5)/256*2*math.pi-math.pi;lat=(y+0.5)/128*math.pi-math.pi/2;theta=math.pi/2-lat
        radius=theta/(120*math.pi/180)*64;sx=64+math.sin(lon)*radius;sy=64+math.cos(lon)*radius
        if theta > 120*math.pi/180 or not (0 <= sx < 128 and 0 <= sy < 128): expected += bytes((0,0,0))
        else: expected += bytes((round(max(0,min(254,(sx-0.5)*2))),round(max(0,min(254,255-sy*2))),40))
assert difference(pixels(frame),expected) < 4, difference(pixels(frame),expected)
full = out/'full.mp4';chunk = out/'chunk.mp4'
full.unlink(missing_ok=True);chunk.unlink(missing_ok=True)
run(exe,'export',source,'--out',full);run(exe,'export',source,'--start',2,'--duration',0.5,'--out',chunk)
assert json.loads(run(exe,'spherical-metadata',full))['sphericalV1']
for file,t,name in [(full,1,'full'),(chunk,0,'chunk')]:run('ffmpeg','-v','error','-y','-i',file,'-ss',t,'-frames:v',1,out/(name+'.png'))
assert difference(pixels(out/'full.png'),pixels(out/'chunk.png')) < 2
assert difference(pixels(out/'chunk.png'),pixels(a)) < 4
print('Spherical workflow: independent pan/fisheye pixels, unchanged video/audio packet hashes, FFprobe spherical marker, automatic full/chunk export passed')
