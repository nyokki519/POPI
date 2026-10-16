#!/usr/bin/env python3
"""Launch the native home screen; publish a small screenshot as CI annotations.
Screenshots contain only this app's UI, never GRAVITY or user screen data.
"""
import subprocess,json,sys,tempfile,base64,time,hashlib,re
from pathlib import Path
app=Path(sys.argv[1])
def run(*args,timeout=120):
    return subprocess.run(args,check=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout).stdout
runtimes=json.loads(run('xcrun','simctl','list','runtimes','available','--json'))['runtimes']
runtime=next(r['identifier'] for r in runtimes if r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS'))
uid=run('xcrun','simctl','create','Floral Reader UI Test','com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation',runtime).strip()
try:
    run('xcrun','simctl','boot',uid)
    run('xcrun','simctl','bootstatus',uid,'-b',timeout=180)
    run('xcrun','simctl','status_bar',uid,'override','--time','9:41','--batteryState','charged','--batteryLevel','100')
    run('xcrun','simctl','install',uid,str(app))
    launched=run('xcrun','simctl','launch',uid,'jp.nyokki519.GravityReader').strip()
    print(launched)
    pid=re.search(r':\s*(\d+)\s*$',launched)
    assert pid,'simctl did not return an application PID'
    # A cold simulator can take longer than three seconds to foreground an app.
    # A successful launch command alone also does not prove the process survived.
    time.sleep(12)
    listing=run('xcrun','simctl','spawn',uid,'launchctl','list')
    running=any(row.split() and row.split()[0]==pid.group(1) for row in listing.splitlines())
    if not running:
        reports=Path.home()/'Library/Logs/DiagnosticReports'
        for report in sorted(reports.glob('GravityReader*'),key=lambda p:p.stat().st_mtime,reverse=True)[:2]:
            text=report.read_text(errors='replace')
            details=[]
            for word in ['"exception"','"termination"','"faultingThread"']:
                index=text.find(word)
                if index>=0:details.append(text[index:index+1000])
            print('::error title=APP_CRASH::'+json.dumps(details,ensure_ascii=False)[:3500])
        raise RuntimeError('Launched app exited before UI screenshot')
    # Re-foreground the surviving app after simulator setup and allow its scene
    # to settle. The screenshot is still inspected by a human after this check.
    print(run('xcrun','simctl','launch',uid,'jp.nyokki519.GravityReader').strip())
    time.sleep(5)
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)/'home.jpg'
        run('xcrun','simctl','io',uid,'screenshot','--type=jpeg',str(p))
        small=Path(tmp)/'home-preview.jpg'
        width=300
        while True:
            run('sips','--resampleWidth',str(width),'-s','formatOptions','20',str(p),'--out',str(small))
            raw=small.read_bytes();data=base64.b64encode(raw).decode()
            # Each workflow step publishes at most ten notices. Reserve one for
            # metadata and keep at most eight chunks, safely under both limits.
            if len(data)<=24000:break
            width-=40
            if width<100:raise RuntimeError('UI preview cannot fit annotation budget')
        # GitHub's annotations truncate messages after 4096 characters.
        size=3000
        print('::notice title=FLORAL_UI_META::'+json.dumps({'chunks':(len(data)+size-1)//size,'sha256':hashlib.sha256(raw).hexdigest()}))
        for i,start in enumerate(range(0,len(data),size)):
            print(f'::notice title=FLORAL_UI_{i:03d}::{data[start:start+size]}')
    print('PASS simulator launch and screenshot; no GRAVITY/ReplayKit runtime assertion')
finally:
    subprocess.run(['xcrun','simctl','shutdown',uid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    subprocess.run(['xcrun','simctl','delete',uid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
