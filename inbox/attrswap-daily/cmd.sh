#!/bin/bash
# forcing-swap seq=17 -- amendment A approved: install the updated V6 check + determinism guard, preserve the
# first attempt's evidence, resubmit the gate and the nine arms. Nothing else changes: code, data shadow,
# basin lists and all ten configs are untouched from the seq=13 deployment.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09
M=$HOME/hpc_mailbox/inbox/attrswap-daily/payload

echo "=== A. PRESERVE ATTEMPT 1 EVIDENCE ==="
[ -f "$R/logs/convert_verify.json" ] && cp "$R/logs/convert_verify.json" "$R/logs/convert_verify.attempt1.json"
[ -f "$R/logs/job_ids.txt" ] && mv "$R/logs/job_ids.txt" "$R/logs/job_ids.attempt1.txt"
ls "$R/logs" | head -20

echo "=== B. SCRIPT CHANGE (hashes before and after) ==="
echo "before: build_era5l_forcing.py $(sha256sum $R/hpc_deploy/build_era5l_forcing.py | cut -c1-16)"
echo "before: fswap_gate.slurm       $(sha256sum $R/hpc_deploy/fswap_gate.slurm | cut -c1-16)"
cp "$M/build_era5l_forcing.py" "$M/fswap_gate.slurm" "$R/hpc_deploy/" || { echo COPY_FAILED; exit 1; }
sed -i 's/\r$//' "$R"/hpc_deploy/build_era5l_forcing.py "$R"/hpc_deploy/fswap_gate.slurm
echo "after:  build_era5l_forcing.py $(sha256sum $R/hpc_deploy/build_era5l_forcing.py | cut -c1-16)"
echo "after:  fswap_gate.slurm       $(sha256sum $R/hpc_deploy/fswap_gate.slurm | cut -c1-16)"
echo "--- the amended V6 block ---"
grep -n -A 8 "off = {b: l for b, l in lags.items()" "$R/hpc_deploy/build_era5l_forcing.py"
grep -n "V6_MIN_LAG0_SHARE = " "$R/hpc_deploy/build_era5l_forcing.py"
echo "--- confirm nothing else moved: the other three payload scripts are unchanged on disk ---"
for f in make_configs.py fswap_train.slurm; do echo "  $f $(sha256sum $R/hpc_deploy/$f | cut -c1-16)"; done

echo "=== C. CONFIGS UNTOUCHED ==="
ls "$R/configs" | wc -l
sha256sum "$R"/configs/*.yml | cut -c1-16 | sort | uniq -c | wc -l
echo "  (10 config files expected; they were generated at seq=13 and are not regenerated)"

echo "=== D. SUBMIT GATE ==="
out=$(sbatch "$R/hpc_deploy/fswap_gate.slurm" 2>&1); echo "$out"
GATE=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$GATE" ] || { echo SUBMIT_FAILED_GATE; exit 1; }
echo "$GATE" > "$R/logs/job_ids.txt"
echo "gate job: $GATE"

echo "=== E. SUBMIT 9 ARMS (afterok:$GATE) ==="
for a in fswap_armE27_s100 fswap_armE27_s200 fswap_armE27_s300 \
         fswap_armE23_s100 fswap_armE23_s200 fswap_armE23_s300 \
         fswap_armEP_s100 fswap_armEP_s200 fswap_armEP_s300; do
  sed -e "s|^#SBATCH -J fswap_arm|#SBATCH -J ${a}|" \
      -e "s|^#SBATCH --exclude=ngu201|#SBATCH --exclude=ngu201\n#SBATCH --dependency=afterok:${GATE}|" \
      -e "s|^set -eo pipefail|set -eo pipefail\nCFG=${a}|" \
      "$R/hpc_deploy/fswap_train.slurm" > "$R/hpc_deploy/jobs/${a}.slurm"
  o=$(sbatch "$R/hpc_deploy/jobs/${a}.slurm" 2>&1)
  j=$(echo "$o" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -z "$j" ]; then echo "SUBMIT_FAILED $a :: $o"; else echo "$a -> $j"; echo "$j" >> "$R/logs/job_ids.txt"; fi
done
echo "job ids: $(tr '\n' ' ' < $R/logs/job_ids.txt)"

echo "=== F. QUEUE ==="
squeue -u "$USER" -o '%.11i %.22j %.9T %.10M %.9N %.20E' 2>&1 | grep -Ei 'fswap|JOBID' || echo '  (none)'
echo "=== DONE ==="
