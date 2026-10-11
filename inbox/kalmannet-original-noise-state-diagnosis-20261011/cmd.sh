#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'EXACT_EXISTING_REPORT_ACCEPTANCE'
import hashlib,json
from pathlib import Path
r=Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/results')
p=r/'review/cases'/'06431500'/'review.json'
b=p.read_bytes()
assert hashlib.sha256(b).hexdigest()=='91597c17cb88d63629de5c016df5df97b0f5eed3c36c011d2337e3c80dffbaf3'
v=json.loads(b)
assert v['status']=='PASS' and v['basin']=='06431500' and not v['findings'] and all(x['passed'] for x in v['checks'])
assert v['contract_sha256']==hashlib.sha256(Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/results/control/contract.json').read_bytes()).hexdigest()=='9af889459145e358afef24f20dd93918cfa261bf7513957b57b586870fd75f36'
assert v['source_review_sha256']==hashlib.sha256(Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/results/review/source_review.json').read_bytes()).hexdigest()=='aeac9a3acfb9ea4173db1a3bb22e99d5b498c087b7edbdb20bb4edb8c3de0e99'
assert v['package_manifest_sha256']==hashlib.sha256(Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/package_manifest.json').read_bytes()).hexdigest()=='41229ee05254080974558af9331bb8b5cf2f329e318414695fe58380e2cd16fa'
assert v['checker_sha256']=='25f2083e808ae54edb5e2a15dd3baa3d22356885d7011dbf03ad334b545b8dde'
assert v['raw_manifest_sha256']==hashlib.sha256((r/'cases'/'06431500'/'attempt_001/raw_manifest.json').read_bytes()).hexdigest()
d=r/'review/accepted'/'06431500.json'
existed=d.exists()
if existed: assert d.read_bytes()==b
d.parent.mkdir(parents=True,exist_ok=True)
if not existed:
 with d.open('xb') as h:h.write(b)
assert d.read_bytes()==b
print('REMOTE_JSON='+json.dumps({'status':'EXISTING_STRICT_CHECK_ACCEPTED','basin':v['basin'],'review_sha256':hashlib.sha256(b).hexdigest(),'scientific_repeated':False,'accepted_report_existed_before':existed}))
EXACT_EXISTING_REPORT_ACCEPTANCE
