#!/usr/bin/env bash
set -euo pipefail
python3 -I -B - <<'PY'
import hashlib,runpy,sys
from pathlib import Path
payload=Path('/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-lr-stability/confirmation-20260914-v1')
expected={
 'study.tar.gz':'98e5536d2ae134a6cdc6bfc48c730b2e196b4bce0f0a3a4ecc2a47857810dc6f',
 'PACKAGE_MANIFEST.json':'4f03bd675bd53c5137a37c9cc0af0110052abdc1fa2819a2a5a8226ead0ec4fd',
 'deploy.py':'014658426d5427409e8b26fa8510c54f661909b6293c5d8ebfd7b9fe14aab905'}
for name,digest in expected.items():
 path=payload/name
 if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
  raise RuntimeError('transport hash mismatch: '+name)
print('LR_STUDY_TRANSPORT_IDENTITY_PASS',flush=True)
sys.argv=[str(payload/'deploy.py'),'--payload',str(payload),'--submit']
runpy.run_path(str(payload/'deploy.py'),run_name='__main__')
PY
