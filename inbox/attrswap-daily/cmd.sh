#!/bin/bash
# Stage-2 SUBMIT (PREREG_20260911 section 6; user-authorized 'approve 4 all'): reference gate + 8 ref_daymet arms,
# then one gate per product + its 3 arms, all on partition hgpu4 (D6). Products listed in PRODUCTS below are those
# that passed the LOCAL pre-submission checks (section 6). Job ids are written to logs/jobs.txt. sbatch is the only
# mutating operation; nothing outside the own landing dir is touched. No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap2_daily_2026_09
PART=hgpu4
PRODUCTS="imerg_refday imerg_uncal_refday imerg_utc gsmap_refday era5l_refday chirps"
cd $R || exit 1
echo "=== A. guards ==="
[ "$(ls runs 2>/dev/null | wc -l)" -eq 0 ] || { echo "ABORT: runs/ not empty"; exit 1; }
[ -f logs/jobs.txt ] && { echo "ABORT: logs/jobs.txt exists (already submitted?)"; exit 1; }
for p in $PRODUCTS; do [ -f hpc_deploy/${p}_daily_529.csv.gz ] || { echo "ABORT: table missing for $p"; exit 1; }; echo "  table $p $(sha256sum hpc_deploy/${p}_daily_529.csv.gz | cut -c1-16)"; done
echo "=== B. set partition in the three templates ==="
sed -i "s/hgpu4/$PART/" hpc_deploy/pswap2_gate_ref.slurm hpc_deploy/pswap2_gate_product.slurm hpc_deploy/pswap2_train.slurm
grep -H '^#SBATCH -p' hpc_deploy/*.slurm | sed 's/^/  /'
echo "=== C. reference gate + 8 arms ==="
gref=$(sbatch --parsable hpc_deploy/pswap2_gate_ref.slurm) || { echo "SBATCH FAILED gate_ref"; exit 1; }
echo "gate_ref $gref" | tee -a logs/jobs.txt
for s in 100 200 300 400 500 600 700 800; do
  j=$(sbatch --parsable --dependency=afterok:$gref --export=ALL,CFG=ref_daymet_s$s,GATE=gate_ref.txt,WRITE_MEDIAN=1 -J ref_daymet_s$s hpc_deploy/pswap2_train.slurm) || { echo "SBATCH FAILED ref s$s"; exit 1; }
  echo "ref_daymet_s$s $j dep=$gref" | tee -a logs/jobs.txt
done
echo "=== D. product gates + 3 arms each ==="
for p in $PRODUCTS; do
  sa=0; case "$p" in imerg_*|gsmap_*|era5l_*) sa=1;; esac
  g=$(sbatch --parsable --export=ALL,PRODUCT=$p,SRC_MODE=table,SELFAGG=$sa -J pswap2_gate_$p hpc_deploy/pswap2_gate_product.slurm) || { echo "SBATCH FAILED gate $p"; exit 1; }
  echo "gate_$p $g selfagg=$sa" | tee -a logs/jobs.txt
  for s in 100 200 300; do
    j=$(sbatch --parsable --dependency=afterok:$g --export=ALL,CFG=pswap2_armP_${p}_s$s,GATE=gate_${p}.txt,WRITE_MEDIAN=0 -J pswap2_armP_${p}_s$s hpc_deploy/pswap2_train.slurm) || { echo "SBATCH FAILED $p s$s"; exit 1; }
    echo "pswap2_armP_${p}_s$s $j dep=$g" | tee -a logs/jobs.txt
  done
done
echo "=== E. queue snapshot ==="
squeue -u "$USER" -o '%.10i %.32j %.9T %.10M %.6D %.9P %R' 2>&1 | grep -Ei 'pswap2|ref_daymet|JOBID' | head -50
echo "  jobs registered: $(wc -l < logs/jobs.txt)"
echo "=== F. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
