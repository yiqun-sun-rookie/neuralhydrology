#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import hashlib,json
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001/execution/v004')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for method in ('gaussian','iterative'):
    folder=root/'records/attacks'/('original_s100_'+method+'_eps0p1_bound_only')/'01022500'
    marker=json.loads((folder/'complete.json').read_text())
    metadata=json.loads((folder/'metadata.json').read_text())
    hashes={name:sha(folder/name) for name in ('complete.json','metadata.json','arrays.npz')}
    assert marker['status']=='complete'
    assert hashes['metadata.json']==marker['metadata_sha256']
    assert hashes['arrays.npz']==marker['arrays_sha256']==metadata['arrays_sha256']
    assert marker['record_id']==metadata['record_id']
    print('HISTORICAL_RESOURCE '+json.dumps(dict(method=method,folder=str(folder),hashes=hashes,marker=marker,metadata=metadata,scope='read existing files and hashes only; no scientific computation')),flush=True)
PY
