#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/kalmannet_wrr_counter_diagnosis_20260928_v1
payload="$HOME/hpc_mailbox/inbox/kalmannet-wrr-counter-hpc-20260928/payload/hpc_counter_diagnosis_package_v1.tar.gz"
echo '=== EXCLUSIVE DEPLOYMENT GATE ==='
test ! -e "$root" || { echo 'ROOT_ALREADY_EXISTS_STOP'; exit 2; }
test -f "$payload" || { echo 'PAYLOAD_MISSING_STOP'; exit 3; }
printf '%s  %s\n' b3a86b32e5bbe1c6ff0801aff3e5dc9f6bfefb113930c36d96007787d7633753 "$payload" | sha256sum -c -
mkdir "$root"
mkdir "$root/logs" "$root/runs" "$root/code"
tar -xzf "$payload" -C "$root/code"
cd "$root/code"
echo '=== IMMUTABLE CODE FILES ==='
printf '%s\n' \
  '02e55d21f1f581baad0f79f93e5a08311689cabb93566c33e22aa51b825d4d73  hpc_driver.py' \
  '7a327bf1bab340a41f937fde582da765e2690ea5079087ed93b8afc2fbdf38df  hpc_summarize.py' \
  '3754f50a7657c2878ae17e45d115e7569cf24c21dd46900c10d4a55f6535cf9a  hpc_experiment_manifest.json' \
  '72fc1de1cc30fdd6fec6f7aabb44179f8d73bf6fde7046d1500f2bc5797d6fd9  job.slurm' \
  '19c94fea3e9b6cca1741856fe6d061a010c7e84dbc8943a9622705bcd3d68785  neural_runtime.py' \
  '001e1c543f3b84fe14dc6b18320c1d9544eeaffc0d7b51a415383a7af040cfb7  evaluate_neural.py' \
  '08f1c04ff265d73e9eee91f02c0776f35157848c236e4577629dbf5792cd3fde  diagnostic_capture.py' | sha256sum -c -
echo '=== SINGLE JOB SUBMISSION ==='
set +e
submission=$(sbatch "$root/code/job.slurm" 2>&1)
submit_status=$?
set -e
printf '%s\n' "$submission" | tee "$root/submission_output.txt"
printf '%s\n' "$submit_status" > "$root/submission_exit.txt"
job_id=$(printf '%s\n' "$submission" | awk '$1=="Submitted" && $2=="batch" && $3=="job" && $4 ~ /^[0-9]+$/ {print $4}')
if [ "$submit_status" -ne 0 ] || ! [[ "$job_id" =~ ^[0-9]+$ ]]; then echo 'SUBMIT_FAILED_NO_RETRY'; exit 4; fi
printf '%s\n' "$job_id" > "$root/job_id.txt"
echo "CONFIRMED_JOB_ID=$job_id"
squeue -h -j "$job_id" -o '%i|%j|%T|%P|%R' || true
