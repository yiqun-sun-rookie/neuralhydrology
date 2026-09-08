#!/bin/bash
# forcing-swap seq=20 -- the gate could not be scheduled because of MY OWN inherited "--exclude=ngu201":
# on hgpu8, ngu202 is in maintenance, ngu203 had 2 idle CPUs, and ngu201 (excluded) was the only node with 8.
# Fix: drop the exclusion (ngu201 is not a faulty node; the playbook's bad node is ngu002, in another partition)
# and lower cpus-per-task 8 -> 4, which matches the config's num_workers: 4 and doubles how many arms fit.
# Neither change touches the frozen contract: model, data, seeds, epochs and all ten configs are untouched.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09

echo "=== A. AVAILABILITY ACROSS THE GPU PARTITIONS (for the record, before deciding) ==="
for p in hgpu8 hgpu4 hgpu2p hgpu2; do
  echo "--- $p ---"
  sinfo -p "$p" -N -o "%.9N %.7t %.18C %.10G" 2>&1 | head -12
done

echo "=== B. CANCEL MY TEN PENDING JOBS (explicit ids only, never -u) ==="
for j in $(cat "$R/logs/job_ids.txt"); do
  st=$(sacct -j "$j" -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  case "$st" in
    PENDING) scancel "$j" && echo "  cancelled $j (PENDING, never started)";;
    RUNNING) echo "  $j is RUNNING -- NOT cancelling, stop and report"; exit 1;;
    *) echo "  $j is $st -- left alone";;
  esac
done
mv "$R/logs/job_ids.txt" "$R/logs/job_ids.attempt2.txt"

echo "=== C. EDIT THE TWO SLURM TEMPLATES (resource lines only) ==="
for f in "$R/hpc_deploy/fswap_gate.slurm" "$R/hpc_deploy/fswap_train.slurm"; do
  echo "  before: $(basename $f) $(sha256sum $f | cut -c1-16)"
  sed -i -e '/^#SBATCH --exclude=ngu201$/d' -e 's|^#SBATCH --cpus-per-task=8$|#SBATCH --cpus-per-task=4|' "$f"
  echo "  after:  $(basename $f) $(sha256sum $f | cut -c1-16)"
  grep -nE "^#SBATCH (-p|--cpus-per-task|--gres|--exclude)" "$f"
done
echo "--- confirm nothing but those two lines moved ---"
grep -c "" "$R/hpc_deploy/fswap_gate.slurm" "$R/hpc_deploy/fswap_train.slurm"

echo "=== D. SUBMIT GATE ==="
out=$(sbatch "$R/hpc_deploy/fswap_gate.slurm" 2>&1); echo "$out"
GATE=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$GATE" ] || { echo SUBMIT_FAILED_GATE; exit 1; }
echo "$GATE" > "$R/logs/job_ids.txt"

echo "=== E. SUBMIT 9 ARMS (afterok:$GATE) ==="
for a in fswap_armE27_s100 fswap_armE27_s200 fswap_armE27_s300 \
         fswap_armE23_s100 fswap_armE23_s200 fswap_armE23_s300 \
         fswap_armEP_s100 fswap_armEP_s200 fswap_armEP_s300; do
  sed -e "s|^#SBATCH -J fswap_arm|#SBATCH -J ${a}|" \
      -e "s|^#SBATCH --gres=gpu:1|#SBATCH --gres=gpu:1\n#SBATCH --dependency=afterok:${GATE}|" \
      -e "s|^set -eo pipefail|set -eo pipefail\nCFG=${a}|" \
      "$R/hpc_deploy/fswap_train.slurm" > "$R/hpc_deploy/jobs/${a}.slurm"
  o=$(sbatch "$R/hpc_deploy/jobs/${a}.slurm" 2>&1)
  j=$(echo "$o" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -z "$j" ]; then echo "SUBMIT_FAILED $a :: $o"; else echo "$a -> $j"; echo "$j" >> "$R/logs/job_ids.txt"; fi
done
echo "job ids: $(tr '\n' ' ' < $R/logs/job_ids.txt)"

echo "=== F. QUEUE + START ESTIMATE ==="
squeue -u "$USER" -o '%.11i %.20j %.9T %.16E %.24R' 2>&1 | grep -Ei 'fswap|JOBID' || echo '  (none)'
echo "  gate start estimate: $(squeue -j $GATE -h --start -o '%S' 2>&1)"
echo "=== DONE ==="
