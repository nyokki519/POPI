#!/usr/bin/env python3
"""Package an unsigned device build for re-signing by AltStore on Windows."""
import sys,zipfile,plistlib,hashlib
from pathlib import Path
app=Path(sys.argv[1]);out=Path(sys.argv[2])
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleSupportedPlatforms']==['iPhoneOS'],'Simulator apps cannot be installed'
assert (app/info['CFBundleExecutable']).is_file()
ext=app/'PlugIns/Upload.appex'
assert (ext/'Upload').is_file() and plistlib.loads((ext/'Info.plist').read_bytes())['NSExtension']['NSExtensionPointIdentifier']=='com.apple.broadcast-services-upload'
assert (app/'Assets.car').is_file(),'App icon catalog is missing'
out.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as z:
 for p in sorted(app.rglob('*')):
  if p.is_file():z.write(p,'Payload/GravityReader.app/'+str(p.relative_to(app)))
with zipfile.ZipFile(out) as z:assert z.testzip() is None
print(out.name,out.stat().st_size,hashlib.sha256(out.read_bytes()).hexdigest())
print('UNSIGNED: requires personal Apple signing before installation; no installation claim.')
