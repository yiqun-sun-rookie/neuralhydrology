#!/bin/bash
set -u
root=/data1/home/sunyiq/id25_graice_shared_c01_20261019_001
old=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
q() { printf '\nQUERY=%s\n' "$*"; timeout 30 "$@"; printf 'QUERY_EXIT=%s\n' "$?"; }
q date -Iseconds
q scontrol -o show job 245242
q squeue -j 245242 --start -o '%i|%P|%T|%r|%S|%R'
q sprio -l -j 245242
q sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -O 'partition:12,nodelist:16,gres:18,gresused:30,cpusstate:24'
q sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -o '%P|%N|%t|%G|%C|%f'
for partition in hgpu2p hgpu2; do q scontrol -o show partition "$partition"; done
for rel in job_id.txt submissions.tsv authorization_policy.json provenance/cpu_contract.json provenance/gpu_preflight.json; do printf '\nFILE=%s\n' "$rel"; cat "$root/$rel"; done
printf '\nENV_PYTHON_LINK\n'; readlink -f "$old/venv/bin/python"
printf '\nENV_REQUIREMENTS\n'; cat "$root/package/requirements-linux.txt"
printf '\nCURRENT_CODE_HASHES\n'; sha256sum "$root"/package/{config.json,scaler_manifest.json,author_model.py,shared_endpoint.py,run_control.py,score_saved.py,requirements-linux.txt} "$root/ops/id25_shared_train_runtime.py"
printf '\nBEGIN_TRAINING_STATE_JSON\n'; PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 "$old/venv/bin/python" "$root/ops/id25_shared_train_runtime.py" inspect "$root"; printf '\nEND_TRAINING_STATE_JSON\n'
echo READ_ONLY_NO_MODEL_PREFLIGHT_NO_JOB_CHANGE
exit 0
