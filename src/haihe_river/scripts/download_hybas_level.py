#!/usr/bin/env python3
import sys
import os
import zipfile
from pathlib import Path
import urllib.request


def download(url: str, dest_dir: Path) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    fn = dest_dir / Path(url).name
    with urllib.request.urlopen(url) as r, open(fn, 'wb') as f:
        f.write(r.read())
    return fn


def unzip(zip_path: Path, dest_dir: Path):
    with zipfile.ZipFile(zip_path, 'r') as z:
        z.extractall(dest_dir)


def main():
    if len(sys.argv) < 2:
        print('usage: download_hybas_level.py <url> [dest_dir]')
        sys.exit(1)
    url = sys.argv[1]
    dest_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path('data/haihe/hydrobasins/source')
    zp = download(url, dest_dir)
    unzip(zp, dest_dir)
    print('OK', zp)


if __name__ == '__main__':
    main()


