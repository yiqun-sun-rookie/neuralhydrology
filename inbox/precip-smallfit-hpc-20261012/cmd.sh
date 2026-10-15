#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -c 'import base64,hashlib,json,zlib
from pathlib import Path
root=Path('"'"'/data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261015T062534Z_26ac3faf_v03'"'"')
marker=json.loads((root/'"'"'records/submission.json'"'"').read_bytes())
assert marker['"'"'job_id'"'"']==242770 and marker['"'"'nonce'"'"']=='"'"'26ac3faff4e34c7ba4eea6e485377376'"'"'
owner=json.loads((root/'"'"'runtime/owner.json'"'"').read_bytes())
assert owner['"'"'status'"'"']=='"'"'STOPPED'"'"'
rows=[]
for name,expected in [('"'"'runtime/direct_control/control/zero_network_baseline.pt'"'"','"'"'c1aa78febf811c4119a64f17c7be5e172bdbae14d73a292ad653b039e75432e8'"'"'),('"'"'runtime/direct_control/context_identity.json'"'"',None)]:
 p=root/name
 assert not p.is_symlink() and p.resolve().is_relative_to(root)
 assert p.stat().st_size<=262144
 raw=p.read_bytes(); digest=hashlib.sha256(raw).hexdigest()
 assert expected is None or digest==expected
 rows.append({'"'"'path'"'"':name,'"'"'bytes'"'"':len(raw),'"'"'sha256'"'"':digest,'"'"'base64'"'"':base64.b64encode(raw).decode()})
print('"'"'SMALLFIT_INIT_ORIGINAL_V01='"'"'+base64.b64encode(zlib.compress(json.dumps({'"'"'job_id'"'"':242770,'"'"'nonce'"'"':'"'"'26ac3faff4e34c7ba4eea6e485377376'"'"','"'"'files'"'"':rows},sort_keys=True).encode())).decode(),flush=True)
'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261015T062534Z_26ac3faf_v03/payload/code/src/precip_input_assimilation/hpc/precip_smallfit_return_v01.py --root /data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261015T062534Z_26ac3faf_v03 --nonce 26ac3faff4e34c7ba4eea6e485377376 --chunk 4 --archive-sha256 b5a585e152de663cca03a65c46d33f0903a6516c0f9a62e6077fdd1e0ab4f7aa
