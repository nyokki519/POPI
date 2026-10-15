#!/usr/bin/env python3
"""Launch the native home screen; publish a small screenshot as CI annotations.
Screenshots contain only this app's UI, never GRAVITY or user screen data.
"""
import subprocess,json,sys,tempfile,base64,time
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
    print(run('xcrun','simctl','launch',uid,'jp.nyokki519.GravityReader').strip())
    time.sleep(3)
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)/'home.jpg'
        run('xcrun','simctl','io',uid,'screenshot','--type=jpeg',str(p))
        data=base64.b64encode(p.read_bytes()).decode()
        for i,start in enumerate(range(0,len(data),45000)):
            print(f'::notice title=FLORAL_UI_{i:03d}::{data[start:start+45000]}')
    print('PASS simulator launch and screenshot; no GRAVITY/ReplayKit runtime assertion')
finally:
    subprocess.run(['xcrun','simctl','shutdown',uid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    subprocess.run(['xcrun','simctl','delete',uid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
