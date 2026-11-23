import json, math, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import imageio_ffmpeg

ROOT=Path('tmp/manual-video'); PARTS=ROOT/'rendered'; PARTS.mkdir(exist_ok=True)
FFMPEG=imageio_ffmpeg.get_ffmpeg_exe()
NAVY=(13,15,34,255); MINT=(143,241,213,255)

def font(n,bold=False):
 return ImageFont.truetype('assets/fonts/Sora-'+('SemiBold' if bold else 'Regular')+'.ttf',n)
def point(x,y): return (140+x*800/1264,170+(y*1560/2736-78)*1560/1404)
def wrap(draw,text,f,width):
 words=text.split();lines=[];line=''
 for word in words:
  attempt=(line+' '+word).strip()
  if draw.textbbox((0,0),attempt,font=f)[2]>width and line: lines.append(line);line=word
  else:line=attempt
 if line:lines.append(line)
 return lines

def overlay(spec,index,event=None):
 im=Image.new('RGBA',(1080,1920),(0,0,0,0));d=ImageDraw.Draw(im)
 if event is None:
  d.rectangle((0,0,1080,168),fill=NAVY);d.rectangle((0,1732,1080,1920),fill=NAVY)
  d.text((60,24),'SPENDLY  /  USER GUIDE',font=font(23),fill=MINT)
  d.text((60,77),spec['title'],font=font(43,True),fill='white')
  d.text((1000,50),str(index).zfill(2),font=font(32,True),fill='#8F8AAE',anchor='ra')
  d.rounded_rectangle((138,168,942,1732),radius=20,outline=(77,75,112,255),width=3)
 else:
  lines=wrap(d,event['text'],font(35),960)
  y=1760+(145-len(lines)*49)/2
  for line in lines:d.text((540,y),line,font=font(35),fill='white',anchor='mt');y+=49
  if 'box' in event:
   x1,y1=point(*event['box'][:2]);x2,y2=point(*event['box'][2:])
   d.rounded_rectangle((x1-3,y1-3,x2+3,y2+3),radius=20,outline=(10,20,30,190),width=10)
   d.rounded_rectangle((x1,y1,x2,y2),radius=18,outline=MINT,width=5)
  targets=event.get('targets', [event['target']] if 'target' in event else [])
  for rawx,rawy,rawr in targets:
   x,y=point(rawx,rawy);r=rawr*800/1264
   d.ellipse((x-r-3,y-r-3,x+r+3,y+r+3),outline=(10,20,30,190),width=11)
   d.ellipse((x-r,y-r,x+r,y+r),outline=MINT,width=6)
   side=1 if x<620 else -1
   start=(max(40,min(1040,x+side*(r+95))),max(170,y-r-95))
   end=(x+side*r*.72,y-r*.72)
   d.line((start,end),fill=MINT,width=7)
   angle=math.atan2(end[1]-start[1],end[0]-start[0]);length=23
   triangle=[end,(end[0]-length*math.cos(angle-.55),end[1]-length*math.sin(angle-.55)),
                 (end[0]-length*math.cos(angle+.55),end[1]-length*math.sin(angle+.55))]
   d.polygon(triangle,fill=MINT)
 return im

def run(args):
 p=subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-y']+args,capture_output=True,text=True)
 if p.returncode: raise RuntimeError(p.stderr)

def encode(spec,index):
 name=spec['name'];end=spec.get('trimEnd',spec['duration']);out=PARTS/(name+'.mp4')
 header=PARTS/(name+'-header.png');overlay(spec,index).save(header)
 args=['-i',str(ROOT/(name+'.mp4')),'-loop','1','-i',str(header)]
 chain='[0:v]trim=end='+str(end)+',setpts=PTS-STARTPTS,fps=24,crop=720:1404:0:78,scale=800:1560,pad=1080:1920:140:170:color=0x0D0F22,setsar=1[base];[base][1:v]overlay=0:0[head]'
 previous='head'
 for n,event in enumerate(spec.get('callouts',[])):
  png=PARTS/(name+'-event-'+str(n)+'.png');overlay(spec,index,event).save(png)
  args+=['-loop','1','-i',str(png)]
  current='event'+str(n)
  chain+=';['+previous+']['+str(n+2)+":v]overlay=0:0:enable='between(t,"+str(event['start'])+','+str(event['end'])+")'["+current+']'
  previous=current
 args+=['-filter_complex',chain,'-map','['+previous+']','-t',str(end),'-an','-c:v','libx264','-preset','veryfast','-crf','22','-threads','2','-pix_fmt','yuv420p','-movflags','+faststart',str(out)]
 run(args);print('Rendered',name,flush=True);return out

def card(name,duration):
 out=PARTS/(name+'.mp4')
 run(['-loop','1','-framerate','24','-i',str(ROOT/(name+'.png')),'-t',str(duration),'-vf','setsar=1,format=yuv420p','-an','-c:v','libx264','-preset','veryfast','-crf','22','-threads','2',str(out)])
 return out

if __name__=='__main__':
 specs=[json.loads(p.read_text(encoding='utf-8')) for p in sorted(ROOT.glob('[0-9][0-9]-*.json'))]
 paths=[card('intro',4)]
 for i,spec in enumerate(specs,1):paths.append(encode(spec,i))
 paths.append(card('outro',4))
 concat=PARTS/'concat.txt';concat.write_text(''.join("file '"+str(p.resolve()).replace('\\','/')+"'\n" for p in paths),encoding='utf-8')
 output=Path('artifacts/Spendly-User-Manual.mp4');output.parent.mkdir(exist_ok=True)
 run(['-f','concat','-safe','0','-i',str(concat),'-c','copy','-movflags','+faststart','-metadata','title=Spendly User Guide',str(output)])
 print('VIDEO:',output.resolve(),flush=True)
