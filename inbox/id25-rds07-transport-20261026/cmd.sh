#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_transport_rds07_20261026_001
exec 9>"$root/submit.lock"
flock -n 9
test -f "$root/submission_intent.initial"
test ! -e "$root/job_id.txt"
test ! -e "$root/output/runtime.json"
test ! -e "$root/submission_intent.memory_default_v004"
active=$(timeout 30 squeue -h -u sunyiq -n id25_rds07_261026 -o '%i|%j|%T')
test -z "$active"
timeout 30 sacct -n -X -j 247680 --format=JobIDRaw,JobName%40,User,State,ExitCode,ElapsedRaw,Start,End,NodeList -P > "$root/failed_submission_247680_v004.txt"
cat "$root/failed_submission_247680_v004.txt"
awk -F'|' '$1=="247680" && $2=="id25_rds07_261026" && $3=="sunyiq" && $4=="FAILED" && $5=="1:0" && $6=="0" {ok++} END {exit(ok!=1)}' "$root/failed_submission_247680_v004.txt"
timeout 30 sacct -n -X -u sunyiq -S 2026-10-26 --format=JobIDRaw,JobName%40,State,ExitCode -P | awk -F'|' '$2=="id25_rds07_261026" {print}' > "$root/pre_repair_sacct_v004.txt"
awk -F'|' '{n++; if($1!="247680" || $3!="FAILED") bad=1} END {exit(n!=1 || bad)}' "$root/pre_repair_sacct_v004.txt"
mkdir "$root/resource_adaptation_v004"
cp "$root/hpc/train.slurm" "$root/resource_adaptation_v004/original_train.slurm"
test "$(grep -c '^#SBATCH --mem=' "$root/hpc/train.slurm")" -eq 1
sed '/^#SBATCH --mem=/d' "$root/hpc/train.slurm" > "$root/hpc/train_memory_default_v004.slurm"
cat > "$root/resource_adaptation_v004/receipt.json" <<'JSON'
{"reason":"seq1 memory request rejected; native accounting retains FAILED/1:0 job247680 with zero elapsed, no runtime or training output. Seq2 guard rejected that terminal accounting record rather than a live job.","change":"Remove explicit scheduler memory request only; retain default allocation and allow the documented failed pre-start accounting record in the submission guard.","original_config_memory_gib":"Rejected request, not actual allocation or RSS limit","scientific_code_changed":false,"scientific_config_changed":false,"training_budget_changed":false,"optimizer_updates_before_repair":0,"previous_job_id":"247680"}
JSON
sha256sum "$root/hpc/train.slurm" "$root/hpc/train_memory_default_v004.slurm"
date -Is > "$root/submission_intent.memory_default_v004"
set +e
sbatch --parsable "$root/hpc/train_memory_default_v004.slurm" > "$root/resource_adaptation_v004/sbatch_response.txt" 2>&1
rc=$?
set -e
cat "$root/resource_adaptation_v004/sbatch_response.txt"
test "$rc" -eq 0
submitted=$(cat "$root/resource_adaptation_v004/sbatch_response.txt")
job=${submitted%%;*}
case "$job" in ''|*[!0-9]*) echo UNRESOLVED_SUBMISSION_RESPONSE; exit 1 ;; esac
printf '%s\n' "$job" > "$root/job_id.txt"
printf '%s\t247680\trejected_memory_request_zero_elapsed\n' "$(cat "$root/submission_intent.initial")" >> "$root/submissions.tsv"
printf '%s\t%s\tmemory_default_v004\n' "$(date -Is)" "$job" >> "$root/submissions.tsv"
printf 'SUBMITTED_JOB=%s\n' "$job"
timeout 30 squeue -h -j "$job" -o '%i|%j|%T|%M|%R'
timeout 30 sacct -n -X -j "$job" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList -P
