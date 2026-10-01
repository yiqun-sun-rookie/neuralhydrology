#!/usr/bin/env bash
# Repair only the private test-tool packaging; preserve the first failed run.
set -eo pipefail
task_base="$HOME/precip_dynamic_filter_20260930"
task_previous="$task_base/run_20261001_211612_19f6cfd5"
task_run="$task_base/run_20261001_222234_hpc_repair1_d27632e6"
task_data="$HOME/neuralhydrology/data/camels_us"
task_payload="$HOME/hpc_mailbox/inbox/precip-dynamic-filter-v03/payload/dynamic_filter_run_20261001_222234_hpc_repair1_d27632e6.tgz"
test -d "$task_data"
test -f "$task_previous/bundle_manifest.json"
test -f "$task_previous/submission_receipt.txt"
test "$(cat "$task_previous/submission_receipt.txt")" = "235197"
task_prior_state=$(sacct -X -n -P -j 235197 --format=JobID,State,ExitCode,ElapsedRaw)
task_prior_state=$(printf '%s' "$task_prior_state" | tr -d ' \r')
printf 'PRIOR_JOB=%s\n' "$task_prior_state"
test "$task_prior_state" = '235197|FAILED|1:0|108'
if test -e "$task_run"; then echo RUN_COLLISION; exit 21; fi
test -f "$task_payload"
task_actual=$(sha256sum "$task_payload")
task_actual=${task_actual%% *}
test "$task_actual" = "abed02753942025babf4a892c579c44b9c0a3718c156c91ee35fa36abe2ee668"
mkdir "$task_run"
task_resolved=$(readlink -f "$task_run")
test "$task_resolved" = "$task_run"
case "$task_resolved" in "$HOME/precip_dynamic_filter_20260930/"*) ;; *) exit 22 ;; esac
tar -xzf "$task_payload" -C "$task_resolved"
mkdir "$task_resolved/logs"
test ! -e "$task_resolved/submission_receipt.txt"
task_reply=$(sbatch --parsable --time=71:58:12 --chdir="$task_resolved/code" --export="ALL,DYNAMIC_RUN_ROOT=$task_resolved,DYNAMIC_DATA_DIR=$task_data" --output="$task_resolved/logs/pilot-%j.out" --error="$task_resolved/logs/pilot-%j.err" "$task_resolved/code/src/precip_input_assimilation/hpc/dynamic_filter_pilot_v03.slurm")
task_job=${task_reply%%;*}
[[ "$task_job" =~ ^[0-9]+$ ]]
printf '%s\n' "$task_reply" > "$task_resolved/submission_receipt.txt"
printf 'JOB_ID=%s\nRUN_ROOT=%s\nPAYLOAD_SHA256=%s\nPRIOR_GPU_SECONDS=108\nREMAINING_GPU_SECONDS=259092\n' "$task_job" "$task_resolved" "$task_actual"
scontrol show job "$task_job"
