"""Read nine exact model artifacts; return a small in-memory transfer archive."""
import base64
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

base = Path('/data1/home/sunyiq/forcing_swap_daily_2026_09/runs')
raw = io.BytesIO()
manifest = {}
with tarfile.open(fileobj=raw, mode='w') as archive:
    for seed in (100, 200, 300):
        source = base / f'fswap_armE23_s{seed}_2026_0908_1745_ep30'
        for name in ('config.yml', 'model_epoch030.pt', 'train_data/train_data_scaler.yml'):
            path = source / name
            data = path.read_bytes()
            arcname = f'seed{seed}/{name}'
            info = tarfile.TarInfo(arcname)
            info.size = len(data)
            info.mtime = 0
            archive.addfile(info, io.BytesIO(data))
            manifest[arcname] = {'source': str(path), 'bytes': len(data),
                                 'sha256': hashlib.sha256(data).hexdigest()}
    data = json.dumps(manifest, sort_keys=True, indent=2).encode()
    info = tarfile.TarInfo('source_manifest.json')
    info.size = len(data)
    archive.addfile(info, io.BytesIO(data))
payload = gzip.compress(raw.getvalue(), compresslevel=1, mtime=0)
assert len(payload) < 5000000, 'Transfer unexpectedly large'
print(json.dumps({'artifacts': len(manifest), 'archive_bytes': len(payload),
                  'archive_sha256': hashlib.sha256(payload).hexdigest()}))
print('BEGIN_MODEL_ARCHIVE_BASE64')
print(base64.b64encode(payload).decode('ascii'))
print('END_MODEL_ARCHIVE_BASE64')
