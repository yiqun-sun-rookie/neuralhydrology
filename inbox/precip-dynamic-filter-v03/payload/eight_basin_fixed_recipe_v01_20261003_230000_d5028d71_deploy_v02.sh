#!/usr/bin/env bash
# Arguments are concrete, reviewed transport identities; this file submits once.
# payload sha256 contract_sha256 new_run_dir data_root python validator validator_sha256
set -eo pipefail
[ "$#" -eq 8 ] || { echo DEPLOY_REQUIRES_EIGHT_ARGUMENTS; exit 20; }
task_payload=$1
task_payload_sha=$2
task_contract_sha=$3
task_run=$4
task_data=$5
task_python=$6
task_validator=$7
task_validator_sha=$8
[[ "$task_payload_sha" =~ ^[0-9a-f]{64}$ ]]
[[ "$task_contract_sha" =~ ^[0-9a-f]{64}$ ]]
[[ "$task_validator_sha" =~ ^[0-9a-f]{64}$ ]]
test -f "$task_payload"
test -f "$task_validator"
test -x "$task_python"
test -d "$task_data"
task_actual=$(sha256sum "$task_validator")
task_actual=${task_actual%% *}
test "$task_actual" = "$task_validator_sha"
task_actual=$(sha256sum "$task_payload")
task_actual=${task_actual%% *}
test "$task_actual" = "$task_payload_sha"
case "$task_run" in "$HOME/precip_dynamic_eight_basins_20261003/"*) ;; *) echo UNREGISTERED_TASK_DIRECTORY; exit 21 ;; esac
case "$task_run" in *".."*|*".worktrees"*) echo NONCANONICAL_TASK_DIRECTORY; exit 22 ;; esac
test ! -e "$task_run"
mkdir -p "$HOME/precip_dynamic_eight_basins_20261003"
mkdir "$task_run"
task_resolved=$(readlink -f "$task_run")
case "$task_resolved" in "$HOME/precip_dynamic_eight_basins_20261003/"*) ;; *) exit 23 ;; esac
task_data=$(readlink -f "$task_data")
mkdir "$task_resolved/logs"
export PYTHONDONTWRITEBYTECODE=1
# Safe archive member/digest checks and help imports are data-free, on the login node.
"$task_python" -B "$task_validator" offline --payload "$task_payload" --sha256 "$task_payload_sha" --output "$task_resolved/payload" > "$task_resolved/offline_acceptance.json"
task_code="$task_resolved/payload/code"
task_contract="$task_code/src/precip_input_assimilation/configs/dynamic_filter_eight_basins_v01.json"
task_actual=$(sha256sum "$task_contract")
task_actual=${task_actual%% *}
test "$task_actual" = "$task_contract_sha"
task_free=$(df -Pk "$task_resolved" | awk 'NR==2 {print $4}')
test "$task_free" -ge 5242880
"$task_python" -B -c 'import json,sys; from pathlib import Path; root=Path(sys.argv[1]); m=json.loads((root/"payload/bundle_manifest.json").read_text()); n=int(m["remaining_gpu_seconds"]//60)*60; assert n>300 and n<=234822; s=(root/"payload/code/src/precip_input_assimilation/hpc/dynamic_filter_eight_basins_v01.slurm").read_text(); s=s.replace("__TASK_TIME__",f"{n//3600:02d}:{n%3600//60:02d}:00"); assert "__TASK_TIME__" not in s; (root/"submission.slurm").open("x").write(s)' "$task_resolved"
export EIGHT_RUN_ROOT="$task_resolved"
export EIGHT_DATA_ROOT="$task_data"
export EIGHT_PAYLOAD_SHA256="$task_payload_sha"
export EIGHT_APPROVED_CONTRACT_SHA256="$task_contract_sha"
export EIGHT_PYTHON="$task_python"
task_reply=$(sbatch --chdir="$task_code" --output="$task_resolved/logs/eight-%j.out" --error="$task_resolved/logs/eight-%j.err" "$task_resolved/submission.slurm" 2>&1)
printf '%s\n' "$task_reply"
task_job=$(printf '%s\n' "$task_reply" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
[[ "$task_job" =~ ^[0-9]+$ ]] || { echo SUBMISSION_NOT_CONFIRMED; exit 24; }
printf '%s\n' "$task_reply" > "$task_resolved/submission_receipt.txt"
printf 'JOB_ID=%s\nRUN_ROOT=%s\nPAYLOAD_SHA256=%s\nCONTRACT_SHA256=%s\n' "$task_job" "$task_resolved" "$task_payload_sha" "$task_contract_sha"
scontrol show job "$task_job"
