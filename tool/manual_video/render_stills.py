import json,subprocess
from pathlib import Path
from PIL import Image
from render import ROOT,PARTS,FFMPEG,NAVY,overlay,run,card

def main():
 specs=json.loads((ROOT/'still-guide.json').read_text(encoding='utf-8'))
 paths=[card('intro',4)]
 for i,spec in enumerate(specs,1):
  source=Image.open(spec['image']).convert('RGBA')
  if spec.get('nativeChrome'): source=source.crop((0,138,source.width,source.height-136))
  source=source.resize((800,1560),Image.Resampling.LANCZOS)
  canvas=Image.new('RGBA',(1080,1920),NAVY);canvas.alpha_composite(source,(140,170))
  canvas.alpha_composite(overlay(spec,i));canvas.alpha_composite(overlay(spec,i,spec))
  png=PARTS/(spec['name']+'-finished.png');canvas.convert('RGB').save(png)
  output=PARTS/(spec['name']+'-guide.mp4');duration=spec.get('duration',5)
  run(['-loop','1','-framerate','24','-i',str(png),'-t',str(duration),
    '-vf','setsar=1,fade=t=in:st=0:d=0.16,fade=t=out:st='+str(duration-.16)+':d=0.16,format=yuv420p',
    '-an','-c:v','libx264','-preset','veryfast','-crf','20','-threads','2','-movflags','+faststart',str(output)])
  paths.append(output);print('Rendered',i,'/',len(specs),spec['name'],flush=True)
 paths.append(card('outro',4))
 concat=PARTS/'stills-concat.txt';concat.write_text(''.join("file '"+str(p.resolve()).replace('\\','/')+"'\n" for p in paths),encoding='utf-8')
 output=Path('artifacts/Spendly-User-Manual.mp4');output.parent.mkdir(exist_ok=True)
 run(['-f','concat','-safe','0','-i',str(concat),'-c','copy','-movflags','+faststart','-metadata','title=Spendly User Guide',str(output)])
 print('VIDEO:',output.resolve(),flush=True)
if __name__=='__main__':main()
