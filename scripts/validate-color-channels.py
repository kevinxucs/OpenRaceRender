#!/usr/bin/env python3
"""Original two-camera RGB write-mask fixture; snapshots, legacy import and encoded frames."""
import copy
import json
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/color-channels/acceptance'
out.mkdir(parents=True,exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'


def run(*args):
    r = subprocess.run(list(map(str,args)),capture_output=True)
    if r.returncode: raise RuntimeError(r.stderr.decode(errors='replace'))
    return r.stdout


def rgb(path): return run('ffmpeg','-v','error','-i',path,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-')


def camera(name,index,bits,opacity):
    return dict(id=str(uuid.uuid4()),name=name,kind='video',style='',inputIndex=index,x=0,y=0,width=100,height=100,opacity=opacity,visible=True,channel='',text='',color='#FFFFFF',minimum=0,maximum=100,start=0,end=1000000,parentIndex=-1,colorChannels=dict(red=bool(bits&1),green=bool(bits&2),blue=bool(bits&4)))


inputs = []
for index,(name,color) in enumerate([('left','0x808080'),('right','0xc8c8c8')]):
    video = out/(name+'.mp4')
    run('ffmpeg','-v','error','-y','-f','lavfi','-i',f'color=c={color}:s=320x180:r=10:d=2','-c:v','libx264','-crf','0','-pix_fmt','yuv420p',video)
    inputs.append(dict(id=str(uuid.uuid4()),name=name,path=str(video),kind='video',legacyIndex=index,duration=2,offset=0,volume=1))
p = dict(formatVersion=1,name='Original stereo channel fixture',width=320,height=180,fps=10,explicitDuration=2,speedUnit='mph',warnings=[],inputs=inputs,objects=[camera('Cyan right eye',1,6,0.75),camera('Red left eye',0,1,0.5)])
source = out/'stereo.orrp';source.write_text(json.dumps(p))
snapshot = out/'stereo.png';run(exe,'snapshot',source,'--time',0.5,'--out',snapshot)
raw = rgb(snapshot)
# Values come independently from the decoded source frames and source-over over black.
l,r = [rgb(out/(name+'.mp4')) for name in ['left','right']]
expected = bytes(round(l[i]*0.5 if i%3 == 0 else r[i]*0.75) for i in range(len(raw)))
assert max(abs(a-b) for a,b in zip(raw,expected)) <= 2
legacy = out/'stereo.rrp';run(exe,'convert',source,'--out',legacy)
reopened = out/'stereo-reopened.png';run(exe,'snapshot',legacy,'--time',0.5,'--width',320,'--out',reopened)
assert max(abs(a-b) for a,b in zip(raw,rgb(reopened))) <= 2
video = out/'stereo-export.mp4';video.unlink(missing_ok=True)
run(exe,'export',source,'--out',video,'--video-bitrate',5000)
encoded = rgb(video);assert sum(abs(a-b) for a,b in zip(raw,encoded))/len(raw) < 3
# A widget mask must retain red/blue beneath a half-opacity green-channel write.
widgets = copy.deepcopy(p)
shape = camera('Green-only widget',-1,2,0.5)
shape.update(kind='shape',shape=dict(kind='rectangle',fill=True,gradient=False,gradientColor='#000000',gradientAngle=90,stroke=False,strokeColor='#FFFFFF',strokeWidth=3,referenceHeight=1080),color='#000000',width=25)
widgets['objects'].append(shape)
widget_project = out/'widget.orrp';widget_project.write_text(json.dumps(widgets))
widget_image = out/'widget.png';run(exe,'snapshot',widget_project,'--time',0.5,'--out',widget_image)
data = rgb(widget_image)
for x in [30,200]:
    i = (90*320+x)*3
    assert abs(data[i]-raw[i]) <= 1 and abs(data[i+2]-raw[i+2]) <= 1
    assert abs(data[i+1]-(raw[i+1]*0.5 if x == 30 else raw[i+1])) <= 2
print('RGB channel workflow passed: independent source-channel arithmetic, alpha, native format reopening, encoded stereo frames, widget preservation.')
