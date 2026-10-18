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
owner=json.loads((root/'runtime/owner.json').read_bytes())
final=json.loads((root/'runtime/final_supervisor_report.json').read_bytes())
assert owner['status']=='STOPPED' and owner['nonce']==nonce and str(owner['job_id'])=='244110'
assert final['numeric_process_exited'] is True and final['budget']['worker_exit_before_settlement'] is True
q=subprocess.run(['sacct','-S','2026-10-16','-X','-j','244110','-n','-P','-o','JobIDRaw,State,ExitCode,ElapsedRaw,NodeList'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=20)
assert q.returncode==0
rows=[l.split('|') for l in q.stdout.decode().splitlines() if l.startswith('244110|')]
assert len(rows)==1 and rows[0][1].split()[0].rstrip('+') in {'FAILED','COMPLETED','TIMEOUT','CANCELLED','OUT_OF_MEMORY','NODE_FAIL','BOOT_FAIL','PREEMPTED','DEADLINE','REVOKED'}
module=runpy.run_path(str(source))
result=module['collect'](root,nonce)
assert result['job_id']==244110 and result['terminal'] is True and result['actual_family_lock_free'] is True and result.get('delivery')
raw=json.dumps(result,sort_keys=True,allow_nan=False).encode()
print('SMALLFIT_RETURN_V01='+base64.b64encode(zlib.compress(raw)).decode(),flush=True)
PY
