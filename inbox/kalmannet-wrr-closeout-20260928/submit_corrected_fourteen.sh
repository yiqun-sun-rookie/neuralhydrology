#!/usr/bin/env bash
# One irreversible submission attempt for the independently admitted 14-case batch.
set -eo pipefail

parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
plain="$parent/plain_preflight_v1"
launch="$parent/corrected_launch_001"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/corrected_fourteen_launch_001.tar
models=(main_seed43 main_seed44 compact_seed42 compact_seed43 compact_seed44 learned_noise hand_tuned)
original_jobs=(229398 229399 229400 229401 229402 229403 229404)
cases=()
for model in "${models[@]}"; do
  cases+=("${model}__corrected_outlet_original_states" "${model}__corrected_outlet_corrected_states")
done

if (( $# != 1 )) || ! [[ "$1" =~ ^[0-9a-f]{64}$ ]]; then
  echo 'EXPECTED_EXACTLY_ONE_PINNED_LOWERCASE_SHA256' >&2
  exit 64
fi
echo 'SCIENTIFIC_ACCEPTANCE=false'
if [[ -e "$launch" || -L "$launch" ]]; then echo REFUSE_EXISTING_LAUNCH >&2; exit 64; fi
for case_id in "${cases[@]}"; do
  output="$plain/numerical_impact/runs/${case_id}__formal_attempt01"
  if [[ -e "$output" || -L "$output" ]]; then echo "REFUSE_EXISTING_OUTPUT=$output" >&2; exit 64; fi
done
for model in "${models[@]}"; do
  original="$plain/numerical_impact/runs/${model}__original_outlet_original_states__formal_attempt01/completion.json"
  if [[ ! -f "$original" ]]; then echo "MISSING_ORIGINAL_COMPLETION=$original" >&2; exit 64; fi
done

# Inspect the whole user queue, but only this exact task-root WorkDir can block this batch.
queue=$(squeue -h -u sunyiq -o '%i|%Z')
active=$(printf '%s\n' "$queue" | awk -F'|' -v root="$parent" '$2 == root || index($2, root "/") == 1 {print}')
if [[ -n "$active" ]]; then printf 'REFUSE_ACTIVE_TASK_JOBS\n%s\n' "$active" >&2; exit 64; fi
for job in "${original_jobs[@]}"; do
  state=$(sacct -n -X -P -j "$job" -o JobID,State,ExitCode)
  if [[ "$state" != "$job|COMPLETED|0:0" ]]; then echo "ORIGINAL_JOB_NOT_COMPLETED=$job:$state" >&2; exit 64; fi
done

printf '%s  %s\n' "$1" "$payload" | sha256sum --strict --check -
# An ordinary tar with this exact reviewed file list is the only accepted payload.
members=(
  corrected_launch_001/submit_corrected_fourteen.sh
  corrected_launch_001/corrected_one.slurm
  corrected_launch_001/independent_launch_review.md
  corrected_launch_001/independent_submit_review.md
  corrected_launch_001/independent_admission_review.md
  corrected_launch_001/corrected_delivery_and_runtime_review.md
  corrected_launch_001/proofs/independent_result_review.md
  corrected_launch_001/proofs/result_acceptance_001.json
  corrected_launch_001/proofs/corrected_scope_independent_review.md
  corrected_launch_001/corrected_state_delivery.json
  corrected_launch_001/launch_files.sha256
)
for case_id in "${cases[@]}"; do members+=("corrected_launch_001/admissions/${case_id}.json"); done
diff -u <(printf '%s\n' "${members[@]}" | LC_ALL=C sort) <(tar -tf "$payload" | LC_ALL=C sort)
tar -tvf "$payload" | awk 'substr($1,1,1) != "-" {exit 1}'
tar --keep-old-files -xf "$payload" -C "$parent"

for case_id in "${cases[@]}"; do
  admission="$launch/admissions/${case_id}.json"
  if [[ ! -s "$admission" || -e "$launch/${case_id}.started" || -L "$launch/${case_id}.started" ]]; then
    echo "MISSING_ADMISSION_OR_EXISTING_MARKER=$case_id" >&2; exit 64
  fi
done
bound=(submit_corrected_fourteen.sh corrected_one.slurm independent_launch_review.md
       independent_submit_review.md independent_admission_review.md
       corrected_delivery_and_runtime_review.md proofs/independent_result_review.md
       proofs/result_acceptance_001.json proofs/corrected_scope_independent_review.md
       corrected_state_delivery.json)
for name in "${bound[@]}"; do
  awk -v wanted="$launch/$name" '$2 == wanted {n++} END {exit n != 1}' "$launch/launch_files.sha256"
done
for case_id in "${cases[@]}"; do
  awk -v wanted="$launch/admissions/${case_id}.json" '$2 == wanted {n++} END {exit n != 1}' "$launch/launch_files.sha256"
done
cd "$plain"
sha256sum --strict --check "$launch/launch_files.sha256"
printf '%s  %s\n' 'dc805a9cb8862f89577120a6757cc838462cd3dc8b98a2eac081284b3cef305f' "$launch/corrected_one.slurm" | sha256sum --strict --check -
sha256sum --strict --check "$plain/package_files.sha256"
sha256sum --strict --check "$plain/formal_launch_001/launch_files.sha256"
test -f "$plain/formal_input_delivery_001_corrected_states/completion.json"
cmp -s "$launch/corrected_state_delivery.json" "$plain/formal_input_delivery_001_corrected_states/completion.json"
test -f "$plain/inputs/repo/docs/plans/wrr-hamid-evaluation-20260927-v1/test_states_001/test_corrected_cpu.pt"

mkdir "$launch/logs"
( set -o noclobber; : > "$launch/submission_attempted" )
previous=
job_list=
declare -A seen_jobs=()
for case_id in "${cases[@]}"; do
  options=(--chdir="$launch" --job-name="knet-corrected-$case_id")
  if [[ -n "$previous" ]]; then options+=("--dependency=afterany:$previous"); fi
  if submission=$(sbatch "${options[@]}" "$launch/corrected_one.slurm" "$case_id" 2>&1); then
    submission_status=0
  else
    submission_status=$?
  fi
  ( set -o noclobber; printf '%s\nexit_status=%s\n' "$submission" "$submission_status" > "$launch/${case_id}.submission_receipt.txt" )
  if (( submission_status != 0 )); then echo "SUBMISSION_FAILED_NO_RETRY=$case_id" >&2; exit 65; fi
  if ! [[ "$submission" =~ ^Submitted\ batch\ job\ ([0-9]+)$ ]]; then
    echo "SUBMISSION_PARSE_FAILED_NO_RETRY=$case_id" >&2; exit 65
  fi
  job=${BASH_REMATCH[1]}
  if [[ -n "${seen_jobs[$job]:-}" ]]; then echo "DUPLICATE_JOB_ID_NO_RETRY=$job" >&2; exit 65; fi
  seen_jobs[$job]=1
  ( set -o noclobber; printf '%s\n' "$job" > "$launch/${case_id}.jobid" )
  echo "CORRECTED_SUBMISSION=$case_id:$job:afterany=${previous:-none}"
  previous="$job"
  job_list="${job_list:+$job_list,}$job"
done
( set -o noclobber; printf '%s\n' "$job_list" > "$launch/all_jobids.txt" )
sacct -n -X -P -j "$job_list" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R|%E' | awk -F'|' -v root="$parent" '$4 == root || index($4, root "/") == 1 {print}'
echo 'SCIENTIFIC_ACCEPTANCE=false'
