#!/usr/bin/env bash
set -eo pipefail
overrides=$(env | awk -F= '$1 ~ /^SBATCH_/ {print $1}')
if [ -n "$overrides" ]; then printf 'REFUSE_SBATCH_ENV_OVERRIDE\n%s\n' "$overrides"; exit 64; fi
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/submit_three_method_035.sh 004bc089ef4b37433fc9b74560ca3e5164e62bb74e951bdf46b82952dc9ead77 4cf03350dc3292851cb81769453b8690ea887a807bc43773431e77adc20ef7b9
