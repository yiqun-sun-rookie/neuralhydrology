#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'STRICT_SAVED_ARRAY_OPERATION'
import hashlib,subprocess,sys
from pathlib import Path
p=Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/verification/v8/remote_saved_review.py')
assert hashlib.sha256(p.read_bytes()).hexdigest()=='77f8f18f31ba20ebe6632729df327a1aa6d6dac8c56b93884dc84c609fdaaeba'
p=subprocess.run(['/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python', '-X', 'utf8', '-B', '/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/verification/v8/remote_saved_review.py', 'export', '--basin', '06431500', '--index', '0'],capture_output=True,text=True,timeout=240)
print(p.stdout,end="",flush=True)
print(p.stderr,end="",file=sys.stderr,flush=True)
raise SystemExit(p.returncode)
STRICT_SAVED_ARRAY_OPERATION
