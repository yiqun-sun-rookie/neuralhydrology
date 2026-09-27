#!/bin/bash
# seq 91: GPM-era contract SINGLE SUBMISSION (PREREG_20260927 section 8): substitute the partition into the two slurm
# files (python, not sed), then gate job -> array of 26 arms (afterok gate, throttle %4 so that jobs already in flight
# are not crowded out). Placeholder __PART__ is replaced by the local wrapper before shipping this file as cmd.sh.
# sbatch is the only mutating operation; only numeric job ids are accepted. No scancel. No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap4_gpm_daily_2026_09
PART=__PART__
case "$PART" in hgpu4|hgpu8|hgpu2p|hgpu2) ;; *) echo "ABORT: PART not substituted / unknown: $PART"; exit 1;; esac
cd $R || exit 1
sub () {
  local out; out=$(sbatch --parsable "$@" 2>&1) || { echo "SBATCH ERROR: $out" >&2; return 1; }
  out=${out%%;*}
  case "$out" in ''|*[!0-9]*) echo "SBATCH REJECTED (no numeric id): $out" >&2; return 1;; esac
  echo "$out"
}
echo "=== A. guards ==="
[ "$(ls runs 2>/dev/null | wc -l)" -eq 0 ] || { echo "ABORT: runs/ not empty"; exit 1; }
[ -f logs/jobs.txt ] && { echo "ABORT: logs/jobs.txt exists (already submitted?)"; exit 1; }
[ "$(grep -c . configs/arms.txt)" -eq 26 ] || { echo "ABORT: arms.txt not 26 lines"; exit 1; }
for c in $(cat configs/arms.txt); do [ -f configs/$c.yml ] || { echo "ABORT: missing config $c"; exit 1; }; done
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - "$PART" <<'PYEOF'
import sys, pathlib
part = sys.argv[1]
for f in ('pswap4_gate.slurm', 'pswap4_train.slurm'):
    p = pathlib.Path('hpc_deploy') / f
    t = p.read_text()
    assert t.count('__PART__') == 1, (f, t.count('__PART__'))
    p.write_text(t.replace('__PART__', part), newline=chr(10))
    print('  partition set in', f)
PYEOF
grep -H '^#SBATCH -p' hpc_deploy/*.slurm | sed 's/^/  /'
echo "=== B. submit gate + array ==="
g=$(sub hpc_deploy/pswap4_gate.slurm) || { echo "SBATCH FAILED gate"; exit 1; }
echo "gate $g" | tee -a logs/jobs.txt
a=$(sub --dependency=afterok:$g --array=0-25%4 hpc_deploy/pswap4_train.slurm) || { echo "SBATCH FAILED array"; exit 1; }
echo "array $a dep=$g tasks=0-25%4" | tee -a logs/jobs.txt
echo "planned_gpu_hours 11.0 cap 20.0 partition $PART submitted $(date '+%F %T')" | tee logs/budget_ledger.txt
squeue -u "$USER" -o '%.14i %.30j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap4|JOBID' | head -10
echo "=== DONE ==="
