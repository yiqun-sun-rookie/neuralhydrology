#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'REMOTE_OPERATION'
import json,subprocess
command=json.loads('["/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python", "-X", "utf8", "-B", "/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/code/remote_state.py", "status", "--basin", "03340800"]')
p=subprocess.run(command,capture_output=True,text=True,timeout=240)
print(p.stdout,end='')
if p.returncode: print('REMOTE_ERROR_JSON='+json.dumps({'exit_code':p.returncode,'stderr':p.stderr,'stdout':p.stdout}))
REMOTE_OPERATION
