#!/usr/bin/env bash
# Export the six original rain ledgers from the already completed pilot.
set -eo pipefail
exec /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
from datetime import datetime, timezone
import base64
import gzip
import hashlib
import io
import json
import tarfile

root = Path('/data1/home/sunyiq/precip_dynamic_filter_20260930/run_20261001_222234_hpc_repair1_d27632e6')
assert root.resolve() == root
assert (root / 'submission_receipt.txt').read_text().strip() == '235201'
assert json.loads((root / 'pilot/complete.json').read_text()) == {
    'stage': 'all', 'success': True, 'automatic_expansion': False}
expected = {
    'historical_s1001': '7121916f17af03aff9919b60fd90ad97b42afd4ebc24f37275ba93f0c8f5462d',
    'historical_s1002': 'd7f0417c7b5eb9afc06eb77642f5f791e94f82964a38e7f9e56c1a706be4ad22',
    'historical_s1003': '61a5fd895d1da0699ef9726772f612252540ee360f474855fc844bc75e0e458c',
    'rain_s1001': 'f5c456292007dbc7926ffe650a5322d7d8bdaceb76d7b9bbb184fe0e3eccac3c',
    'rain_s1002': '4e7d6d316d79e1b93b9942528f5f848ea4cbd4c7ef1c702706b67c626cc6ef44',
    'rain_s1003': '1de3cbb29fd9bde28a94670a1b81edd4d6ad523958b527ffafa3b2836af4cf50'
}
stream, manifest = io.BytesIO(), {}
with tarfile.open(fileobj=stream, mode='w') as archive:
    for method, identity in sorted(expected.items()):
        path = root / 'pilot/scoring' / method / 'rain_versions.csv'
        assert path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(root)
        raw = path.read_bytes()
        assert len(raw) < 40 * 1024 * 1024 and hashlib.sha256(raw).hexdigest() == identity
        name = path.relative_to(root).as_posix()
        manifest[name] = {'bytes': len(raw), 'sha256': identity}
        info = tarfile.TarInfo(name)
        info.size, info.mtime, info.mode = len(raw), 0, 0o444
        archive.addfile(info, io.BytesIO(raw))
    content = json.dumps({'collected_at_utc': datetime.now(timezone.utc).isoformat(),
                          'job': 235201, 'root': root.as_posix(), 'files': manifest}, indent=2).encode()
    info = tarfile.TarInfo('rain_collection_manifest.json')
    info.size, info.mtime, info.mode = len(content), 0, 0o444
    archive.addfile(info, io.BytesIO(content))
payload = gzip.compress(stream.getvalue(), compresslevel=3, mtime=0)
assert len(payload) < 55 * 1024 * 1024, 'Preserve originals and split export if receipt exceeds the bound.'
print('TRANSFER_JSON=' + json.dumps({'bytes': len(payload),
      'sha256': hashlib.sha256(payload).hexdigest(), 'files': len(manifest),
      'raw_csv_bytes': sum(item['bytes'] for item in manifest.values())}))
print('ARCHIVE_BASE64_BEGIN')
print(base64.b64encode(payload).decode())
print('ARCHIVE_BASE64_END')
print('READ_ONLY_RAIN_EXPORT_COMPLETE')
PY
