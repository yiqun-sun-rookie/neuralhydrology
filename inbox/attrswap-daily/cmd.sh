#!/bin/bash
# Stage-2 Amendment B propagation (PREREG_20260911 14.3): reinstall the amended scripts in the OWN landing dir
# precip_swap2_daily_2026_09 and regenerate the 41 configs under the '_refday' names. NO sbatch. Sealed dirs read-only.
# No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap2_daily_2026_09
PL=$HOME/hpc_mailbox/inbox/attrswap-daily/payload/pswap2
[ -d "$R" ] || { echo "ABORT: $R missing"; exit 1; }
echo "=== A. guard: nothing trained yet in this landing dir ==="
echo "  runs entries: $(ls $R/runs 2>/dev/null | wc -l)  runs_smoke: $(ls $R/runs_smoke 2>/dev/null | wc -l)  logs: $(ls $R/logs 2>/dev/null | wc -l)"
[ "$(ls $R/runs 2>/dev/null | wc -l)" -eq 0 ] || { echo "ABORT: runs/ not empty"; exit 1; }
echo "=== B. reinstall amended scripts ==="
cp $PL/build_precip_swap2.py $PL/make_pswap2_configs.py $PL/pswap2_gate_ref.slurm $PL/pswap2_gate_product.slurm $PL/pswap2_train.slurm $PL/v9_streamflow.py $PL/scripts_public_median.py $R/hpc_deploy/
for f in $R/hpc_deploy/*.py $R/hpc_deploy/*.slurm; do echo "  $(sha256sum $f | cut -c1-16) $(basename $f)"; done
echo "=== C. regenerate configs (old names removed first; own landing dir) ==="
old=$(ls $R/configs/*.yml 2>/dev/null | wc -l); echo "  old configs: $old"
rm -f $R/configs/*.yml
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
cd $R && python hpc_deploy/make_pswap2_configs.py 2>&1 | tail -2
echo "  configs now: $(ls $R/configs/*.yml | wc -l)"
ls $R/configs | sed 's/^/    /' | head -50
echo "  --- forcings lines of the 8 product arms (seed 100) ---"
for p in imerg_refday imerg_uncal_refday imerg_utc gsmap_refday gsmap_uncal_refday persiann chirps era5l_refday; do echo "    $p: $(grep -A1 '^forcings' $R/configs/pswap2_armP_${p}_s100.yml | tail -1)"; done
echo "=== D. partitions now ==="
sinfo -p hgpu4,hgpu8 -o '%P %.6D %.10T %.20G %.30N' 2>&1 | sed 's/^/  /'
echo "=== E. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
