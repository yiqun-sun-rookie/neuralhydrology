#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import base64,hashlib,json
from pathlib import Path
root=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2');folder=root/'summary_request_transport_v1'
assert root.is_dir() and not root.is_symlink() and folder.is_dir() and not folder.is_symlink()
assert (root/'OWN_SUMMARY_JOB_ID.txt').read_text().strip()=='241367'
raw=(folder/'BYTE_TRANSPORT_RESULT.json').read_bytes();report=json.loads(raw)
assert report['source_hpc_job_id']=='241367' and report['record_count']==32 and len(report['packets'])==2
assert report['source_requests']==report['new_generated_requests']==report['new_cpu_jobs']==report['scientific_functions_executed']==0
row=report['packets'][1];assert row['name']=='part02.tar.gz'
packet=(folder/row['name']).read_bytes();assert len(packet)==row['bytes']<=4194304 and hashlib.sha256(packet).hexdigest()==row['sha256']
print('OWN_SUMMARY_BYTE_TRANSPORT_REPORT_BEGIN');print(raw.decode());print('OWN_SUMMARY_BYTE_TRANSPORT_REPORT_END')
print('OWN_SUMMARY_PART2_SHA256='+row['sha256'])
print('OWN_SUMMARY_PART2_BASE64_BEGIN');print(base64.b64encode(packet).decode());print('OWN_SUMMARY_PART2_BASE64_END')
print('OWN_SUMMARY_BYTE_PART2_READ_DONE')
PY
