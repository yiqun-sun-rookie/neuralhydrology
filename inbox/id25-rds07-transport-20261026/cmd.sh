#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_transport_rds07_20261026_001
exec 9>"$root/submit.lock"
flock -n 9
test -f "$root/submission_intent.initial"
test ! -e "$root/job_id.txt"
test ! -e "$root/output/runtime.json"
test ! -e "$root/submission_intent.memory_default_v002"
active=$(timeout 30 squeue -h -u sunyiq -n id25_rds07_261026 -o '%i|%j|%T')
test -z "$active"
timeout 30 sacct -n -X -u sunyiq -S 2026-10-26 --format=JobIDRaw,JobName%40,State,ExitCode -P | awk -F'|' '$2=="id25_rds07_261026" {print}' > "$root/pre_repair_sacct_v002.txt"
test ! -s "$root/pre_repair_sacct_v002.txt"
mkdir "$root/resource_adaptation_v002"
cp "$root/hpc/train.slurm" "$root/resource_adaptation_v002/original_train.slurm"
sed '/^#SBATCH --mem=/d' "$root/hpc/train.slurm" > "$root/hpc/train_memory_default_v002.slurm"
test "$(grep -c '^#SBATCH --mem=' "$root/hpc/train.slurm")" -eq 1
cat > "$root/resource_adaptation_v002/receipt.json" <<'JSON'
{"reason":"seq1 explicit sbatch memory-request rejection before any job was accepted","change":"Remove explicit Slurm memory request; use platform default allocation","original_config_memory_gib":"16 was a rejected scheduler request, not an actual allocation or implemented RSS limit","scientific_code_changed":false,"scientific_config_changed":false,"training_budget_changed":false,"new_optimizer_updates_before_repair":0}
JSON
sha256sum "$root/hpc/train.slurm" "$root/hpc/train_memory_default_v002.slurm"
date -Is > "$root/submission_intent.memory_default_v002"
submitted=$(sbatch --parsable "$root/hpc/train_memory_default_v002.slurm")
job=${submitted%%;*}
case "$job" in ''|*[!0-9]*) echo UNRESOLVED_SUBMISSION_RESPONSE; exit 1 ;; esac
printf '%s\n' "$job" > "$root/job_id.txt"
printf '%s\t%s\tmemory_default_v002\n' "$(date -Is)" "$job" >> "$root/submissions.tsv"
printf 'SUBMITTED_JOB=%s\n' "$job"
