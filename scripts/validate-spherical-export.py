#!/usr/bin/env python3
"""Original flattened panorama: native workspace bytes, reopening pixels and marked export."""
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/spherical-export/acceptance'
out.mkdir(parents=True,exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    result = subprocess.run(list(map(str,args)),capture_output=True)
    if result.returncode: raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


def pixels(file): return run('ffmpeg','-v','error','-i',file,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')


media = out/'original.mp4'
run('ffmpeg','-v','error','-y','-f','lavfi','-i','testsrc2=s=480x240:r=10:d=4','-c:v','libx264','-crf','0','-pix_fmt','yuv420p',media)
video = dict(id=str(uuid.uuid4()),name='Flattened camera',kind='video',style='',inputIndex=0,x=-100,y=-100,width=300,height=300,opacity=1,visible=True,channel='',text='',color='#FFFFFF',minimum=0,maximum=100,start=0,end=1000000,parentIndex=-1)
shape = copy.deepcopy(video);shape.update(id=str(uuid.uuid4()),name='Outside center',kind='shape',inputIndex=-1,x=-75,y=125,width=80,height=40,color='#FF0000')
picture = dict(left=0,right=0,top=0,bottom=0,flipX=False,flipY=False,rotation=0,maintainAspect=True,brightness=1,contrast=1,saturation=1,legacyColorInterpretation=True)
p = dict(formatVersion=1,name='Original spherical export',sphericalWorkspace=True,width=480,height=240,fps=10,explicitDuration=4,rangeStart=1,rangeEnd=3,speedUnit='m/s',warnings=[],inputs=[dict(id=str(uuid.uuid4()),name='Camera',path=str(media),kind='video',legacyIndex=0,duration=4,offset=0,volume=1,picture=picture)],objects=[video,shape])
source = out/'original.orrp';source.write_text(json.dumps(p))
for extension,offset in [('rrp',2126),('rrt',12)]:
    native = out/('authored.'+extension)
    run(exe,'convert',source,'--out',native)
    assert native.read_bytes()[offset] == 6
    reopened = out/(extension+'-reopened.orrp')
    run(exe,'convert',native,'--out',reopened)
    q = json.loads(reopened.read_text())
    assert q['sphericalWorkspace'] and (q['width'],q['height']) == (3840,1920)
    assert any(o['x'] == -75 and o['y'] == 125 for o in q['objects'])
    if extension == 'rrt':
        # Template inputs are roles. Binding the camera belongs to the receiving project.
        q['inputs'][0].update(path=str(media),duration=4,picture=picture)
        q['explicitDuration'] = 4
        reopened.write_text(json.dumps(q))
    for time in [0,2.5]:
        a,b = out/f'original-{time}.png',out/f'{extension}-{time}.png'
        run(exe,'snapshot',source,'--width',480,'--time',time,'--out',a)
        run(exe,'snapshot',reopened,'--width',480,'--time',time,'--out',b)
        assert pixels(a) == pixels(b),(extension,time)
full,chunk = out/'full.mp4',out/'chunk.mp4'
full.unlink(missing_ok=True);chunk.unlink(missing_ok=True)
native = out/'authored.rrp'
run(exe,'export',native,'--width',480,'--fps',10,'--out',full)
run(exe,'export',native,'--width',480,'--fps',10,'--start',2,'--duration',0.5,'--out',chunk)
for file in [full,chunk]: assert json.loads(run(exe,'spherical-metadata',file))['sphericalV1']
for file,time,name in [(full,1,'full'),(chunk,0,'chunk')]:run('ffmpeg','-v','error','-y','-i',file,'-ss',time,'-frames:v',1,out/(name+'.png'))
a,b = pixels(out/'full.png'),pixels(out/'chunk.png')
assert sum(abs(x-y) for x,y in zip(a,b))/len(a) < 2
# Optional ignored native-saved baseline supplies a separate encoding oracle.
baseline = root/'build/validation/spherical/native-panoramic-baseline.rrp'
if baseline.exists(): assert baseline.read_bytes()[2126] == native.read_bytes()[2126]
print('Native 360 workspace passed: mode 6, expanded geometry, exact RRP/RRT reopening pixels, marked full/chunk frames and spherical metadata. Live native reopen remains unverified.')
