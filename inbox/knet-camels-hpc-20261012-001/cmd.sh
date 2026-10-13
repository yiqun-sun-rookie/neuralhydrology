#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GET_EXISTING_TRACE'
import io,tarfile,hashlib,json,base64,sys
from pathlib import Path
root=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/origins_041_20261013_001')
path=root/'runs/attempt_002/trace__anchor_long.npz'
assert path.is_file() and not path.is_symlink()
raw=path.read_bytes();stream=io.BytesIO()
with tarfile.open(fileobj=stream,mode='w:gz') as tar:
    item=tarfile.TarInfo('runs/attempt_002/trace__anchor_long.npz');item.size=len(raw);item.mtime=0;item.mode=0o644;tar.addfile(item,io.BytesIO(raw))
data=stream.getvalue()
print('ARTIFACT_ARCHIVE_METADATA='+json.dumps(dict(files=1,bytes=len(data),sha256=hashlib.sha256(data).hexdigest())))
print('ARTIFACT_ARCHIVE_BASE64='+base64.b64encode(data).decode())
GET_EXISTING_TRACE
