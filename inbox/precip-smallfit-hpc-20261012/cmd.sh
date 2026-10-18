#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
timeout 180 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
import base64,hashlib,json,runpy,subprocess,zlib
root=Path('/data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261016T145315Z_af5f130f_v04')
nonce='af5f130f182c4c38ab020520c5374004'
source=root/'payload/code/src/precip_input_assimilation/hpc/precip_smallfit_return_v01.py'
assert not source.is_symlink() and hashlib.sha256(source.read_bytes()).hexdigest()=='2388e9301c6b28eb7f2609ba13e9cde2a9629b1528267671f88eafb449436dea'
marker=json.loads((root/'records/submission.json').read_bytes())
assert marker['job_id']==244110 and marker['nonce']==nonce
indices=[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
archive='a9461329738783f119309a223eeb1e5f4f9e945225e517b915b841b604c053cc'
index=json.loads((root/'delivery/terminal_index_v01.json').read_bytes())
assert index['sha256']==archive and index['chunk_bytes']==262144
assert 1<=len(indices)<=24 and indices==list(range(indices[0],indices[0]+len(indices))) and 0<=indices[0]<=indices[-1]<len(index['chunks'])
module=runpy.run_path(str(source))
chunks=[module['collect'](root,nonce,k,archive) for k in indices]
assert all(x['job_id']==244110 and x['index']==k for x,k in zip(chunks,indices))
result=dict(kind='owned_chunk_batch_v01',job_id=244110,nonce=nonce,archive_sha256=archive,indices=indices,chunks=chunks)
raw=json.dumps(result,sort_keys=True,allow_nan=False).encode()
print('SMALLFIT_RETURN_V01='+base64.b64encode(zlib.compress(raw)).decode(),flush=True)
PY
