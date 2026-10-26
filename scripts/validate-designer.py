#!/usr/bin/env python3
"""Synthetic import/design/audio/loop acceptance; requires a built app and ffmpeg."""
import json, subprocess, struct, uuid, array, math, copy
from pathlib import Path
root = Path(__file__).resolve().parents[1]
out = root/'build/validation/designer'
out.mkdir(parents=True, exist_ok=True)
exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'
def run(*args):
 result = subprocess.run(list(map(str,args)), capture_output=True)
 if result.returncode:
  raise RuntimeError(f"{args[0]} failed: {result.stderr.decode(errors='replace')}")
 return result.stdout
def uid():return str(uuid.uuid4())
run('ffmpeg','-v','error','-y','-f','lavfi','-i','color=c=0x183044:s=640x360:r=30:d=3','-f','lavfi','-i','aevalsrc=0.15*sin(2*PI*440*t)|0.15*sin(2*PI*880*t):s=48000:d=3','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac','-shortest',out/'stereo.mp4')
(out/'design-data.csv').write_text('Time,RPM,Speed (mph),Throttle\n0,1000,0,0\n1,3500,30,40\n2,6000,60,80\n3,7500,80,100\n')
def u32(b,p,v):struct.pack_into('<I',b,p,v)
def f32(b,p,v):struct.pack_into('<f',b,p,v)
def f64(b,p,v):struct.pack_into('<d',b,p,v)
def text(b,p,n,v):
 d=str(v).encode('utf-16le');b[p:p+n]=d+bytes(n-len(d))
def source(name,path,typ):
 b=bytearray(2216);text(b,0,128,name);text(b,128,2048,path);b[2176]=typ;b[2178]=255;u32(b,2180,640|(360<<16));f32(b,2184,3);f32(b,2196,356400);f32(b,2204,1)
 s=bytearray(11312 if typ==4 else 56)
 if typ==4:f32(s,128,1);f32(s,904,1);s[1595]=7
 else:s[0]=100;s[1]=100;s[25:28]=bytes([100]*3);s[30]=100;s[43]=255;f32(s,44,45)
 return b+s
def obj(name,typ,source,payload,x,y,w,h,mode=0):
 b=bytearray(348);text(b,0,128,name);u32(b,256,0xffffffff)
 for p,v in [(260,x),(264,y),(268,w),(272,h)]:f32(b,p,v)
 b[280]=typ;b[281]=2;b[282]=source;b[283]=mode;b[284]=1;b[288]=7;b[292]=100;b[293]=100
 if typ==30:b[285]=1;u32(b,296,640|(640<<16))
 u32(b,344,len(payload));return b+payload+bytes(4)
g=bytearray(712);text(g,0,128,'RPM');text(g,128,128,'RPM')
for p,v in [(256,0),(264,8000),(272,1000),(280,250),(288,6500),(672,1000)]:f64(g,p,v)
struct.pack_into('<Hh',g,296,270,45)
for p,v in [(300,0x121820),(304,0xffffff),(308,0xffffff),(312,0xffffff),(320,0xffffff),(328,0xff4444),(332,0xffffff),(336,0xffffff),(344,0xffffffff),(348,0xffffffff),(680,0xff8844),(684,0xaaaaaa),(692,0xffffff)]:u32(g,p,v)
text(g,352,128,'Helvetica');text(g,480,128,'Helvetica')
for p,v in [(608,20),(612,40),(664,22)]:f32(g,p,v)
for p,v in [(616,1),(617,1),(618,2),(619,144),(622,2),(623,4),(624,140),(625,246),(626,18),(627,191),(628,6),(629,2),(630,1),(633,15),(635,1),(669,3),(670,80),(671,251),(688,15),(689,8)]:g[p]=v
t=bytearray(808);u32(t,0,0xffffff);text(t,4,512,'GAUGE DESIGN / TYPOGRAPHY / SHAPES');text(t,516,128,'Helvetica');f32(t,644,28);t[648]=1
b=bytearray(2152);b[:4]=b'RRP3'
u32(b,4,20191031);u32(b,8,20161216)
for p,v in [(12,2152),(16,2),(20,2216),(24,11312),(28,56),(32,3),(36,344),(40,24),(44,208)]:u32(b,p,v)
b[2120]=1;b[2121]=255;b[2126]=2
b+=source('Stereo video',out/'stereo.mp4',1)+source('Data',out/'design-data.csv',4)
b+=obj('Video',10,0,b'',0,0,100,100)+obj('RPM dial',30,1,g,5,5,25,44.444444)+obj('Title',13,255,t,4,85,92,10)+bytes(12)
(out/'acceptance.rrp').write_bytes(b)
run(exe,'convert',out/'acceptance.rrp','--out',out/'acceptance.orrp')
p=json.loads((out/'acceptance.orrp').read_text());p.pop('legacyData',None);p.pop('sourcePath',None);p['width']=1280;p['height']=720
for i in p['inputs']:i['path']=str(out/i['path']) if not Path(i['path']).is_absolute() else i['path']
gauge=p['objects'][1];gauge['gauge']['rotation']=45;gauge['gauge']['design']['smoothing']=0
# Preserve every encoded setting, then edit the modes exactly as the UI does.
second=copy.deepcopy(gauge);second['id']=uid();second['x']=37.5;second['name']='Dual needle';second['gauge']['design']['mode']='dualNeedle'
gauge['gauge']['design']['mode']='needle';gauge['name']='Needle'
third=copy.deepcopy(gauge);third['id']=uid();third['x']=70;third['name']='Filled gauge';third['gauge']['design']['mode']='filled'
third['gauge']['design']['needleColor']='#5EE0B5'
shape = dict(id=uid(), name='Gradient diamond', kind='shape', style='', x=45, y=58,
             width=10, height=18, visible=True, opacity=1, inputIndex=-1, channel='',
             text='', color='#5EE0B5', minimum=0, maximum=100, parentIndex=-1, start=0, end=1000000,
             shape=dict(kind='diamond', fill=True, gradient=True, gradientColor='#246EAA',
                        gradientAngle=45, stroke=True, strokeColor='#FFFFFF', strokeWidth=2,
                        referenceHeight=720))
p['objects']=[p['objects'][0],gauge,second,third,shape,p['objects'][2]]
p['objects'][-1]['segments']=[dict(id=uid(),time=0.9,text='TIMELINE TITLE CHANGED / AUDIO MUTED')]
p['objects'][0]['segments']=[dict(id=uid(),time=0.9,audio=dict(volume=0,balance=0,routing='stereo'))]
p['inputs'][0]['audio']=dict(volume=1,balance=0,routing='left')
path=out/'designer-showcase.orrp';path.write_text(json.dumps(p,indent=2))
run(exe,'snapshot',path,'--time',0.5,'--out',out/'designer-showcase.png')
video=out/'designer-showcase.mp4'
if video.exists():video.unlink()
run(exe,'export',path,'--start',0,'--duration',2,'--out',video)
def audio(file,at):
 a=array.array('f',run('ffmpeg','-v','error','-ss',at,'-t',0.2,'-i',file,'-vn','-ac',2,'-ar',48000,'-f','f32le','-'))
 return list(a[0::2]),list(a[1::2])
def rms(a):return math.sqrt(sum(x*x for x in a)/max(1,len(a)))
l,r=audio(video,0.2);print('audio left routing',rms(l),rms(r),rms([a-b for a,b in zip(l,r)]),flush=True)
assert rms(l)>0.02 and rms(r)>0.02
assert rms([a-b for a,b in zip(l,r)])<0.002,'Source left-to-both routing was not applied'
l,r=audio(video,1.2);print('muted timeline',rms(l),rms(r),flush=True);assert max(rms(l),rms(r))<0.002,'Timeline audio gain was not applied'
# Repeated source must remain visible beyond the first interval, including a nonzero export start.
p['objects']=[p['objects'][0]];p['objects'][0].pop('segments',None);p['inputs'][0]['audio']['routing']='swap';p['inputs'][0]['timing']=dict(trimStart=0,trimEnd=0.5,projectStart=0,rate=1,loop=True);p['explicitDuration']=2.25
path=out/'loop-routing.orrp';path.write_text(json.dumps(p,indent=2));video=out/'loop-routing.mp4'
if video.exists():video.unlink()
run(exe,'export',path,'--start',0.625,'--duration',1.5,'--out',video,'--width',320,'--fps',10)
for at in [0.1,0.6,1.1]:
 pixels=run('ffmpeg','-v','error','-ss',at,'-i',video,'-frames:v',1,'-f','rawvideo','-pix_fmt','rgb24','-');v=pixels[(90*320+160)*3:(90*320+160)*3+3];print('loop frame',at,list(v),flush=True);assert max(v)>30,'Repeated video turned black'
l,r=audio(video,0.2)
def power(a,hz):
 n=len(a);real=sum(x*math.cos(2*math.pi*hz*i/48000) for i,x in enumerate(a));imag=sum(x*math.sin(2*math.pi*hz*i/48000) for i,x in enumerate(a));return math.hypot(real,imag)/max(1,n)
print('swap energy',power(l,880),power(l,440),power(r,440),power(r,880),flush=True)
assert power(l,880)>power(l,440)*5 and power(r,440)>power(r,880)*5,'Stereo swap was not applied'
print('PASS native designer video, left/mono routing, timed audio mute, looping and stereo swap',flush=True)
