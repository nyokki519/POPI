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
