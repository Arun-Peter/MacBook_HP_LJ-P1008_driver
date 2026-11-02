#!/usr/bin/env python3
"""Developer packaging tool. Python is not needed to install the release."""
import hashlib
from pathlib import Path
import sys
import zipfile

root = Path(__file__).resolve().parent
out = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'dist'
out.mkdir(parents=True, exist_ok=True)
name = 'HP-P1008-macOS-arm64-v1.0.0'
archive = out / (name + '.zip')
top_files = ['README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'VALIDATION.md', 'CHANGELOG.md']
files = [root / f for f in top_files]
for p in sorted((root / 'driver').rglob('*')):
    if not p.is_file() or p.name == '.DS_Store' or p.suffix in {'.dl', '.acl', '.dmg'}:
        continue
    if any(part.endswith('.dSYM') for part in p.parts):
        continue
    files.append(p)
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in files:
        # Flatten driver/ so Install.command is next to README in the download.
        relative = p.relative_to(root / 'driver') if p.is_relative_to(root / 'driver') else p.relative_to(root)
        z.write(p, str(Path(name) / relative))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert not any(n.endswith(('.dl', '.acl', '.dmg')) for n in z.namelist())
    assert f'{name}/src/rastertoxqx.c' in z.namelist()
    assert f'{name}/payload/rastertoxqx' in z.namelist()
    assert f'{name}/Install.command' in z.namelist()
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(out / 'SHA256SUMS.txt').write_text(f'{digest}  {archive.name}\n')
print(f'{archive}\n{digest}\n{len(files)} files; firmware excluded; source included')
