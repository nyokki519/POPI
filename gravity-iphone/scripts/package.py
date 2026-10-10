#!/usr/bin/env python3
from pathlib import Path
import zipfile,hashlib,json
root=Path(__file__).resolve().parents[1]
destination=root/'dist/GravityReader-iPhone-source.zip'
files=sorted(p for p in root.rglob('*') if p.is_file() and 'dist' not in p.relative_to(root).parts and 'xcuserdata' not in p.relative_to(root).parts and '.DS_Store' not in p.name)
manifest={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED) as z:
 for p in files:z.write(p,'GravityReader-iPhone/'+str(p.relative_to(root)))
 z.writestr('GravityReader-iPhone/SHA256SUMS.json',json.dumps(manifest,indent=2,ensure_ascii=False))
with zipfile.ZipFile(destination) as z:
 assert z.testzip() is None
 for name,digest in manifest.items():assert hashlib.sha256(z.read('GravityReader-iPhone/'+name)).hexdigest()==digest
print(destination.name,destination.stat().st_size,hashlib.sha256(destination.read_bytes()).hexdigest())
