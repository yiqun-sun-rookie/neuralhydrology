#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'STRICT_SAVED_ARRAY_OPERATION'
import hashlib,subprocess,sys
from pathlib import Path
p=Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/verification/r10/remote_saved_review.py')
assert hashlib.sha256(p.read_bytes()).hexdigest()=='814a29f555b559ae7171deaeddea2c984e0c0f839a41cf85e05c574dda4543b6'
p=subprocess.run(['/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python', '-X', 'utf8', '-B', '/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/verification/r10/remote_saved_review.py', 'export', '--basin', '01583500', '--index', '0'],capture_output=True,text=True,timeout=240)
print(p.stdout,end="",flush=True)
print(p.stderr,end="",file=sys.stderr,flush=True)
raise SystemExit(p.returncode)
STRICT_SAVED_ARRAY_OPERATION
