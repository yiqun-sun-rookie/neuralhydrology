#!/bin/bash
# seq 96: GPM-era contract ADDENDUM (gsmap_uncal_refday, 3 arms): install the addendum payload into the existing
# landing dir WITHOUT touching any existing file (every target is checked for absence first), generate the 3+1
# addendum configs, then submit gate_add -> array 0-2%3 (afterok) on hgpu4. No scancel. No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap4_gpm_daily_2026_09
PL=$HOME/hpc_mailbox/inbox/attrswap-daily/payload/pswap4_add
cd $R || { echo "ROOT MISSING"; exit 1; }
sub () {
  local out; out=$(sbatch --parsable "$@" 2>&1) || { echo "SBATCH ERROR: $out" >&2; return 1; }
  out=${out%%;*}
  case "$out" in ''|*[!0-9]*) echo "SBATCH REJECTED (no numeric id): $out" >&2; return 1;; esac
  echo "$out"
}
echo "=== 0. probe ==="
squeue -u "$USER" -o '%.14i %.30j %.9T %.10M %.9P %R' 2>&1 | head -20
sinfo -p hgpu4 -N -O nodelist,gres:14,gresused:24,statelong:12 2>&1 | sed 's/^/  /'
echo "=== A. guards ==="
[ -d "$PL" ] || { echo "ABORT: payload missing"; exit 1; }
[ -f logs/gate_ok.txt ] || { echo "ABORT: original gate marker missing"; exit 1; }
[ "$(find runs -path '*/test/model_epoch030/test_metrics.csv' | wc -l)" -eq 26 ] || { echo "ABORT: original 26 arms not all present"; exit 1; }
for f in hpc_deploy/pswap4_gate_add.slurm hpc_deploy/pswap4_train_add.slurm hpc_deploy/gsmap_uncal_refday_daily_132.csv.gz configs/arms_add.txt configs/configs_manifest_add.json logs/gate_add_ok.txt logs/jobs_add.txt data_shadow/camels_us/basin_mean_forcing/gsmap_uncal_refday; do
  [ -e "$f" ] && { echo "ABORT: target exists: $f"; exit 1; }
done
ls runs | grep -q gsmap_uncal && { echo "ABORT: gsmap_uncal run dir exists"; exit 1; }
hm=$(sha256sum hpc_deploy/make_pswap4_configs.py | cut -c1-16)
echo "  make_pswap4_configs.py before: $hm"
echo "=== B. install ==="
cp "$PL/pswap4_gate_add.slurm" "$PL/pswap4_train_add.slurm" "$PL/gsmap_uncal_refday_daily_132.csv.gz" hpc_deploy/
cp "$PL/make_pswap4_configs.py" hpc_deploy/make_pswap4_configs_add.py
for f in hpc_deploy/pswap4_gate_add.slurm hpc_deploy/pswap4_train_add.slurm hpc_deploy/gsmap_uncal_refday_daily_132.csv.gz hpc_deploy/make_pswap4_configs_add.py; do echo "  $(sha256sum $f | cut -c1-16) $(basename $f)"; done
grep -H '^#SBATCH -p' hpc_deploy/pswap4_gate_add.slurm hpc_deploy/pswap4_train_add.slurm | sed 's/^/  /'
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python hpc_deploy/make_pswap4_configs_add.py --addendum 2>&1 | tail -2
cat configs/arms_add.txt | sed 's/^/  /'
diff configs/pswap4_armG_gsmap_refday_s200.yml configs/pswap4_armG_gsmap_uncal_refday_s200.yml | sed 's/^/  /'
echo "=== C. submit ==="
g=$(sub hpc_deploy/pswap4_gate_add.slurm) || { echo "SBATCH FAILED gate_add"; exit 1; }
echo "gate_add $g" | tee -a logs/jobs_add.txt
a=$(sub --dependency=afterok:$g --array=0-2%3 hpc_deploy/pswap4_train_add.slurm) || { echo "SBATCH FAILED array_add"; exit 1; }
echo "array_add $a dep=$g tasks=0-2%3" | tee -a logs/jobs_add.txt
echo "planned_gpu_hours 1.2 cap 3.0 partition hgpu4 submitted $(date '+%F %T')" | tee -a logs/jobs_add.txt
squeue -u "$USER" -o '%.14i %.30j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap4|JOBID'
echo "=== DONE ==="
