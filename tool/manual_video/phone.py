import sys, json, time, subprocess, re, xml.etree.ElementTree as ET
from pathlib import Path

SERIAL = 'emulator-5580'
ADB = ['adb', '-s', SERIAL]
ROOT = Path('tmp/manual-video')
ROOT.mkdir(parents=True, exist_ok=True)

def adb(*args, **kwargs):
    return subprocess.run(ADB + list(args), check=True, creationflags=subprocess.CREATE_NO_WINDOW, **kwargs)

def snapshot(name):
    path = ROOT / (name + '.png')
    with path.open('wb') as f:
        adb('exec-out', 'screencap', '-p', stdout=f)
    print(path.resolve())

def labelled(label):
    adb('shell', 'uiautomator', 'dump', '/sdcard/Download/spendly-manual-window.xml', stdout=subprocess.DEVNULL)
    data=subprocess.check_output(ADB+['exec-out','cat','/sdcard/Download/spendly-manual-window.xml'])
    root=ET.fromstring(data)
    matches=[]
    for node in root.iter('node'):
        fields=[node.get('text',''),node.get('content-desc','')]
        if any(label==' '.join(f.split()) for f in fields):
            bounds=list(map(int,re.findall(r'\d+',node.get('bounds',''))))
            if len(bounds)==4 and bounds[2]>bounds[0] and bounds[3]>bounds[1]:matches.append(bounds)
    if not matches: raise RuntimeError('Visible control not found: '+label)
    bounds=matches[-1]
    adb('shell','input','tap',str((bounds[0]+bounds[2])//2),str((bounds[1]+bounds[3])//2))

def action(item):
    kind = item['kind']
    if kind == 'label': labelled(item['label'])
    elif kind == 'tap': adb('shell', 'input', 'tap', str(item['x']), str(item['y']))
    elif kind == 'swipe': adb('shell', 'input', 'swipe', *map(str, item['points']))
    elif kind == 'back': adb('shell', 'input', 'keyevent', '4')
    elif kind == 'text': adb('shell', 'input', 'text', item['text'].replace(' ', '%s'))
    elif kind == 'key': adb('shell', 'input', 'keyevent', str(item['code']))
    else: raise ValueError(kind)
    time.sleep(.45)

if __name__ == '__main__':
    if sys.argv[1] == 'snapshot': snapshot(sys.argv[2])
    elif sys.argv[1] == 'tap': action({'kind':'tap','x':int(sys.argv[2]),'y':int(sys.argv[3])})
    elif sys.argv[1] == 'back': action({'kind':'back'})
    elif sys.argv[1] == 'swipe': action({'kind':'swipe','points':list(map(int,sys.argv[2:]))})
    elif sys.argv[1] == 'text': action({'kind':'text','text':sys.argv[2]})
    elif sys.argv[1] == 'record':
        spec=json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
        name=spec['name']; remote='/sdcard/Download/spendly-manual-'+name+'.mp4'
        duration=spec['duration']
        proc=subprocess.Popen(ADB+['shell','screenrecord','--size','720x1560','--bit-rate','6M','--time-limit',str(duration),remote],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
        start=time.monotonic()
        actual=[]
        for item in spec.get('actions',[]):
            time.sleep(max(0, item['at']-(time.monotonic()-start)))
            action(item)
            actual.append({**item,'actual':round(time.monotonic()-start,3)})
        out,err=proc.communicate(timeout=duration+15)
        if proc.returncode: raise RuntimeError(err.decode(errors='replace'))
        adb('pull',remote,str(ROOT/(name+'.mp4')))
        (ROOT/(name+'-timing.json')).write_text(json.dumps(actual,indent=2),encoding='utf-8')
        snapshot(name+'-end')
