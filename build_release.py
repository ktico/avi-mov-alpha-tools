"""Create platform ZIPs, including executable bits for Finder .command launchers."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parent
dist = root / 'dist'
dist.mkdir(exist_ok=True)
for platform in ('windows', 'mac'):
    path = dist / f'avi-mov-alpha-tools-{platform}-v1.0.0.zip'
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.write(root / 'README.md', 'avi-mov-alpha-tools/README.md')
        for source in sorted((root / platform).rglob('*')):
            if not source.is_file(): continue
            name = 'avi-mov-alpha-tools/' + source.relative_to(root / platform).as_posix()
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            mode = 0o755 if source.suffix in ('.command', '.sh') else 0o644
            info.external_attr = (0o100000 | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, source.read_bytes())
    print(path.name)
