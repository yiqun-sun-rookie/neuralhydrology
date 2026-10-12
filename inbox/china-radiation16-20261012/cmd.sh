#!/bin/bash
set -eo pipefail
ROOT='/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1'
test -d "$ROOT"
test ! -L "$ROOT"
test ! -e "$ROOT/OWN_SUMMARY_JOB_ID.txt"
test ! -e "$ROOT/summary_requests_v1"
test -d "$ROOT/raw_responses_v1"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json
from pathlib import Path
root=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1')
for row in json.loads("[{\"name\": \"hpc_summary_builder.py\", \"bytes\": 7479, \"sha256\": \"02067548869086b5532574ba2e5b2069b4233cbcaf4d65a283ecf90ee3662005\"}, {\"name\": \"hpc_radiation_reconstruct.py\", \"bytes\": 11335, \"sha256\": \"e3d787184a3584234884984eb274135631be6e1fa92d3b7193ac11f0887d280b\"}, {\"name\": \"hpc_independent_radiation_review.py\", \"bytes\": 22962, \"sha256\": \"8d740c1d5ca5e5a3543c07ff58931de6d4d4e8a468345b5f82c75813de829e9d\"}, {\"name\": \"summary_requests.sbatch\", \"bytes\": 921, \"sha256\": \"bdbe3a98560bd38af75232974594f5be630d007048458ad8c4e0456302d55282\"}, {\"name\": \"radiation_numerical.sbatch\", \"bytes\": 935, \"sha256\": \"acf29430e3d6605f5f06c3db2454fc93a6128e638321e7f315e0051081aaf0e4\"}, {\"name\": \"radiation_independent.sbatch\", \"bytes\": 948, \"sha256\": \"be8a47d203eeadcd8fa265022b60790b63b2a7db608a626182973f9b733ee8ce\"}, {\"name\": \"hpc_request_builder.py\", \"bytes\": 8819, \"sha256\": \"13aee1977d3ada5eda7e771338cbb5e4dfd4ecd31cd26d1400ae094b0e06712f\"}, {\"name\": \"FAILED_BATCH_INPUTS.json\", \"bytes\": 375103, \"sha256\": \"08dd954e645ec34442c874483e5e1fdbc3f862e72c2cb9e106e75a88ca301ae9\"}]"):
    data=(root/row['name']).read_bytes()
    assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256']
for row in [
    {'name': 'ALGORITHMS_RESPONSE_BODY.bin', 'bytes': 823173,
     'sha256': '74d59ec8ff9194bcfa8f2e4bcdd8fed9422bb36ef10cf9d665a7482b3b80763d'},
    {'name': 'ALGORITHMS_TRANSFER_RESULT.json', 'bytes': 429,
     'sha256': 'a65e481c5bb8cc8eacc31bd240697775c6ad9579041c9f30dee064e1bb043695'},
]:
    data=(root/row['name']).read_bytes()
    assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256']
print('OWN_RUNTIME_HASH_CHECKS_PASS')
PY
mkdir -p "$ROOT/logs"
set +e
task_submit=$(sbatch "$ROOT/summary_requests.sbatch" 2>&1)
task_exit=$?
set -e
printf '%s\n' "$task_submit"
printf 'OWN_SUMMARY_SUBMIT_EXIT=%s\n' "$task_exit"
test "$task_exit" = 0
if [[ "$task_submit" =~ ^Submitted\ batch\ job\ ([0-9]+)$ ]]; then
    task_job=${BASH_REMATCH[1]}
else
    printf 'OWN_SUBMIT_JOB_ID_INVALID\n'
    exit 1
fi
printf '%s\n' "$task_job" > "$ROOT/OWN_SUMMARY_JOB_ID.txt"
printf 'OWN_REQUEST_BUILD_JOB_ID=%s\nOWN_SUMMARY_JOB_ID=%s\n' "$task_job" "$task_job"
printf 'OWN_SUMMARY_SUBMIT_DONE\n'
