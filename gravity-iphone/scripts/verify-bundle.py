#!/usr/bin/env python3
"""Check built bundle metadata, not signing or installability on a device."""
import plistlib,sys
from pathlib import Path
root=Path(sys.argv[1])
for bundle,kind in [(root,'APPL'),(root/'PlugIns/Upload.appex','XPC!')]:
    info=plistlib.loads((bundle/'Info.plist').read_bytes())
    executable=info.get('CFBundleExecutable')
    if not isinstance(executable,str) or not executable or '/' in executable or '$(' in executable:
        raise SystemExit(f'{bundle.name}: missing/invalid CFBundleExecutable: {executable!r}')
    binary=bundle/executable
    if not binary.is_file() or binary.stat().st_size==0:
        raise SystemExit(f'{bundle.name}: executable file missing: {executable}')
    if info.get('CFBundlePackageType')!=kind:
        raise SystemExit(f'{bundle.name}: incorrect CFBundlePackageType')
    print(f'PASS {bundle.name}: executable={executable}, metadata and binary exist (signature not tested)')

if not (root/'FloralBackground.png').is_file():
    raise SystemExit('Floral background missing from app resources')
if (root/'PlugIns/Upload.appex/FloralBackground.png').exists():
    raise SystemExit('Floral background must not be included in broadcast extension')
for bundle in (root,root/'PlugIns/Upload.appex'):
    info=plistlib.loads((bundle/'Info.plist').read_bytes())
    if info.get('CFBundleDisplayName')!='オカマ読み上げスッキリアプリ':
        raise SystemExit(f'{bundle.name}: incorrect display name')
print('PASS renamed app and extension; photograph included in app only')
