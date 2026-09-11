#!/bin/bash
# Stage-2 DEPLOY (PREREG_20260911 sections 5/6, user-authorized 'approve 4 all'): create the NEW landing dir
# precip_swap2_daily_2026_09, link the shadow data (daymet directly, streamflow/attributes via attr_swap), copy the
# archived code, install the deploy scripts, generate the 41 configs. NO sbatch in this command. The three sealed
# landing dirs are only read. No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap2_daily_2026_09
A=/data1/home/sunyiq/attr_swap_daily_2026_09
PL=$HOME/hpc_mailbox/inbox/attrswap-daily/payload/pswap2
echo "=== A. guard: landing dir must not exist yet ==="
if [ -e "$R" ]; then echo "ABORT: $R already exists"; ls -la "$R" | head; exit 1; fi
[ -d "$PL" ] || { echo "ABORT: payload dir missing: $PL"; exit 1; }
echo "=== B. create landing dir + shadow links ==="
mkdir -p $R/logs $R/runs $R/runs_smoke $R/configs $R/hpc_deploy $R/basin_lists $R/data_shadow/camels_us/basin_mean_forcing
ln -s /data1/home/sunyiq/neuralhydrology/data/camels_us/basin_mean_forcing/daymet $R/data_shadow/camels_us/basin_mean_forcing/daymet
ln -s $A/data_shadow/camels_us/usgs_streamflow $R/data_shadow/camels_us/usgs_streamflow
ln -s $A/data_shadow/camels_us/camels_attributes_v2.0 $R/data_shadow/camels_us/camels_attributes_v2.0
ls -l $R/data_shadow/camels_us $R/data_shadow/camels_us/basin_mean_forcing | sed 's/^/  /'
dang=$(find -L $R/data_shadow -type l 2>/dev/null)
if [ -n "$dang" ]; then echo "DANGLING: $dang"; exit 1; else echo "  dangling links: none"; fi
echo "  daymet files through link: $(find -L $R/data_shadow/camels_us/basin_mean_forcing/daymet -name '*_forcing_leap.txt' | wc -l)"
echo "  streamflow files through chain: $(find -L $R/data_shadow/camels_us/usgs_streamflow -name '*_streamflow_qc.txt' | wc -l)"
echo "  attribute files: $(ls $R/data_shadow/camels_us/camels_attributes_v2.0/ | wc -l)"
echo "=== C. archived code (copied from attr_swap, hash-checked) ==="
cp -r $A/code_1f9804e $R/code_1f9804e
echo "  files: $(find $R/code_1f9804e -type f | wc -l)"
echo "  camelsus.py sha: $(sha256sum $R/code_1f9804e/neuralhydrology/datasetzoo/camelsus.py | cut -c1-16) (expect 51e2e02b382ec103)"
echo "=== D. install scripts + basin lists ==="
cp $PL/build_precip_swap2.py $PL/make_pswap2_configs.py $PL/pswap2_gate_ref.slurm $PL/pswap2_gate_product.slurm $PL/pswap2_train.slurm $PL/v9_streamflow.py $PL/scripts_public_median.py $R/hpc_deploy/
cp $PL/basin_lists/basins_529.txt $PL/basin_lists/holdout_107.txt $PL/basin_lists/basins_5.txt $PL/basin_lists/caravan_timezone_529.csv $R/basin_lists/
for f in $R/hpc_deploy/* $R/basin_lists/*; do echo "  $(sha256sum $f | cut -c1-16) $(basename $f)"; done
echo "=== E. generate configs (nh_final python) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
cd $R && python hpc_deploy/make_pswap2_configs.py 2>&1 | tail -4
echo "  configs: $(ls $R/configs/*.yml | wc -l)"
echo "  --- diff base vs ref_daymet_s100 (allowed keys only) ---"
diff $A/configs/attrswap_ref27_parity_s900.yml $R/configs/ref_daymet_s100.yml | sed 's/^/  /'
echo "=== F. partitions right now (D6: pick one for all 32 arms) ==="
sinfo -p hgpu4,hgpu8 -o '%P %.6D %.10T %.20G %.30N' 2>&1 | sed 's/^/  /'
squeue -p hgpu4,hgpu8 -o '%.10P %.9T %.6D %.20b' 2>&1 | awk 'NR>1{c[$1" "$2]+=1} END{for(k in c) print "  queued/running jobs", k, c[k]}'
echo "=== G. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
