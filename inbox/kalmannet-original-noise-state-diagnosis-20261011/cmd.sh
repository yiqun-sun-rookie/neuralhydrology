#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'SAVED_REVIEW_OPERATION'
import json,subprocess
argv=json.loads('["/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python", "-X", "utf8", "-B", "/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/verification/v3/remote_saved_review.py", "status"]')
p=subprocess.run(argv,capture_output=True,text=True,timeout=240)
print(p.stdout,end="")
if p.returncode: print('REMOTE_ERROR_JSON='+json.dumps({'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}))
SAVED_REVIEW_OPERATION
