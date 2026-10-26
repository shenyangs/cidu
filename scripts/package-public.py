#!/usr/bin/env python3
"""Package only explicitly reviewed public files; never walk private/runtime data."""
import hashlib
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'VERSION').read_text().strip()
BUILD = (ROOT / 'BUILD_NUMBER').read_text().strip()
if not re.fullmatch(r'\d+\.\d+\.\d+', VERSION) or not BUILD.isdigit():
    raise SystemExit('Invalid release version')

manifest = ROOT / 'scripts/public-files.txt'
names = [s.strip() for s in manifest.read_text().splitlines() if s.strip() and not s.startswith('#')]
if len(names) != len(set(names)):
    raise SystemExit('Duplicate public manifest entry')
top_files = {'.gitignore', 'LICENSE', 'LICENSE.ime-lexicon', 'README.md', 'README.en.md', 'CONTRIBUTING.md', 'THIRD_PARTY.md', 'VERSION', 'BUILD_NUMBER'}
folders = {'.github', 'Sources', 'Tests', 'scripts', 'skills', 'docs', 'fixtures', 'experiments', 'vendor'}
for name in names:
    rel = PurePosixPath(name)
    if rel.is_absolute() or '..' in rel.parts or str(rel) != name:
        raise SystemExit('Invalid public manifest path')
    if name not in top_files and (len(rel.parts) < 2 or rel.parts[0] not in folders):
        raise SystemExit('Path outside public source roots')
    if set(rel.parts) & {'build', 'dist', 'private', 'exports', '__pycache__', '.git'}:
        raise SystemExit('Runtime/private path in public manifest')
    current = ROOT
    for part in rel.parts:
        current = current / part
        if current.is_symlink():
            raise SystemExit('Symlinks are forbidden in public source packages')
    if not current.is_file() or current.stat().st_size > 32 * 1024 * 1024:
        raise SystemExit('Missing or oversized public source file')
    if current.suffix.lower() in {'.dat', '.bin', '.exe', '.dmg', '.p12', '.p8', '.pem', '.key'}:
        raise SystemExit('Binary/private material in public manifest')
required = top_files | {'scripts/public-files.txt', 'scripts/package-public.py', 'scripts/build.sh', 'skills/cidu-migrate/SKILL.md'}
if not required.issubset(names):
    raise SystemExit('Public manifest is missing release inputs')

app = ROOT / 'build/词渡.app'
if app.exists():
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')) != (VERSION, BUILD):
        raise SystemExit('Built app version differs from release inputs; rebuild first')
    if (app / 'Contents/Resources/cidu-migrate/SKILL.md').read_bytes() != (ROOT / 'skills/cidu-migrate/SKILL.md').read_bytes():
        raise SystemExit('Built app Skill differs from public Skill; rebuild first')

out = ROOT / 'dist'
out.mkdir(exist_ok=True)

def package(filename, members):
    fd, temp = tempfile.mkstemp(prefix='.public-', suffix='.zip', dir=out)
    os.close(fd)
    try:
        with zipfile.ZipFile(temp, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for name, path in sorted(members.items()):
                item = zipfile.ZipInfo(name)  # Stable timestamp; public packages are reproducible.
                item.create_system = 3
                mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
                item.external_attr = (0o100000 | mode) << 16
                item.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(item, path.read_bytes())
        with zipfile.ZipFile(temp) as archive:
            if archive.testzip() is not None or set(archive.namelist()) != set(members):
                raise SystemExit('Public package verification failed')
            for name, path in members.items():
                if archive.read(name) != path.read_bytes():
                    raise SystemExit('Public source changed while packaging')
        os.replace(temp, out / filename)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

prefix = f'Cidu-{VERSION}'
package(f'{prefix}-source.zip', {'cidu/' + name: ROOT / name for name in names})
package(f'{prefix}-agent-skill.zip', {'cidu-migrate/SKILL.md': ROOT / 'skills/cidu-migrate/SKILL.md'})
artifacts = [out / f'{prefix}{suffix}' for suffix in ('-macOS-arm64.dmg', '-macOS-arm64.zip', '-source.zip', '-agent-skill.zip')]
checksums = ''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in artifacts if p.is_file())
(out / f'{prefix}-SHA256.txt').write_text(checksums)
print(f'PASS public source ({len(names)} files), Skill, byte verification and checksums: {out.name}/{prefix}-source.zip')
