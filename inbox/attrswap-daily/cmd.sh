#!/bin/bash
# precip-swap -- deploy the isolated landing dir, build configs, submit gate + 6 arms (afterok).
# Code, basin lists and the Maurer / streamflow / attribute / era5l_caravan shadow all reference the
# already-verified forcing_swap landing; the only new input is the shipped CHIRPS table.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap_daily_2026_09
F=/data1/home/sunyiq/forcing_swap_daily_2026_09
M=$HOME/hpc_mailbox/inbox/attrswap-daily/payload

echo "=== A. LANDING ==="
if [ -d "$R" ]; then
  if [ -d "$R/runs" ] && [ -n "$(ls -A $R/runs 2>/dev/null)" ]; then echo "LANDING HAS RUNS -- refusing"; exit 1; fi
  mv "$R" "${R}.OLD_$(date +%Y%m%d_%H%M%S)" && echo "旧落点已改名保留，未删除"
fi
mkdir -p "$R"/logs "$R"/runs "$R"/runs_smoke "$R"/configs "$R"/basin_lists "$R"/hpc_deploy/jobs \
         "$R"/data_shadow/camels_us/basin_mean_forcing

echo "=== B. CODE ==="
cp -r "$F/code_1f9804e" "$R/" || { echo CODE_COPY_FAILED; exit 1; }
find "$R/code_1f9804e" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null
nf=$(find "$R/code_1f9804e" -type f | wc -l); ok=1
echo "source files: $nf (expect 78)"; [ "$nf" = "78" ] || ok=0
for spec in 'neuralhydrology/datasetzoo/camelsus.py:51e2e02b382ec103' \
            'neuralhydrology/modelzoo/cudalstm.py:27f2e17d3f388a9b'; do
  p=${spec%%:*}; want=${spec##*:}; got=$(sha256sum "$R/code_1f9804e/$p" | cut -c1-16)
  echo "  $p $got (expect $want)"; [ "$got" = "$want" ] || ok=0
done
[ "$ok" = "1" ] || { echo CODE_VERIFY_FAILED; exit 1; }

echo "=== C. SHADOW ==="
ln -s "$F/data_shadow/camels_us/usgs_streamflow" "$R/data_shadow/camels_us/usgs_streamflow"
ln -s "$F/data_shadow/camels_us/camels_attributes_v2.0" "$R/data_shadow/camels_us/camels_attributes_v2.0"
ln -s "$F/data_shadow/camels_us/basin_mean_forcing/maurer" "$R/data_shadow/camels_us/basin_mean_forcing/maurer"
ln -s "$F/data_shadow/camels_us/basin_mean_forcing/era5l_caravan" \
      "$R/data_shadow/camels_us/basin_mean_forcing/era5l_caravan"
echo "maurer 可见 $(find -L "$R/data_shadow/camels_us/basin_mean_forcing/maurer" -name '*_forcing_leap.txt' | wc -l) (expect 675)"
echo "era5l_caravan 可见 $(find -L "$R/data_shadow/camels_us/basin_mean_forcing/era5l_caravan" -name '*_forcing_leap.txt' | wc -l) (expect 529)"

echo "=== D. LISTS + PAYLOAD ==="
cp "$F/basin_lists/basins_529.txt" "$F/basin_lists/holdout_107.txt" "$F/basin_lists/basins_5.txt" "$R/basin_lists/"
cp "$F/scripts_public_median.py" "$R/"
sb=$(sha256sum "$R/basin_lists/basins_529.txt" | cut -c1-16)
echo "basins_529 sha $sb (expect 98018c03b0295a56)"
[ "$sb" = "98018c03b0295a56" ] || { echo BASIN_LIST_MISMATCH; exit 1; }
cp "$M"/build_precip_swap.py "$M"/make_pswap_configs.py "$M"/pswap_gate.slurm "$M"/pswap_train.slurm \
   "$M"/chirps_daily_529.csv.gz "$R/hpc_deploy/" || { echo PAYLOAD_COPY_FAILED; exit 1; }
sed -i 's/\r$//' "$R"/hpc_deploy/*.py "$R"/hpc_deploy/*.slurm
for f in "$R"/hpc_deploy/*; do
  [ -f "$f" ] && echo "  $(basename $f) $(sha256sum $f | cut -c1-16) $(stat -c%s $f) 字节"
done

echo "=== E. CONFIGS ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python -u "$R/hpc_deploy/make_pswap_configs.py" || { echo CONFIG_GEN_FAILED; exit 1; }
echo "--- 与基准配置的逐行差异（应只有允许的那几行）---"
diff /data1/home/sunyiq/attr_swap_daily_2026_09/configs/attrswap_ref27_parity_s900.yml \
     "$R/configs/pswap_armP_chirps_s100.yml"

echo "=== F. SUBMIT GATE ==="
out=$(sbatch "$R/hpc_deploy/pswap_gate.slurm" 2>&1); echo "$out"
GATE=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$GATE" ] || { echo SUBMIT_FAILED_GATE; exit 1; }
echo "$GATE" > "$R/logs/job_ids.txt"

echo "=== G. SUBMIT 6 ARMS (afterok:$GATE) ==="
for a in pswap_armP_chirps_s100 pswap_armP_chirps_s200 pswap_armP_chirps_s300 \
         pswap_armP_era5l_s100 pswap_armP_era5l_s200 pswap_armP_era5l_s300; do
  sed -e "s|^#SBATCH -J pswap_arm|#SBATCH -J ${a}|" \
      -e "s|^#SBATCH --gres=gpu:1|#SBATCH --gres=gpu:1\n#SBATCH --dependency=afterok:${GATE}|" \
      -e "s|^set -eo pipefail|set -eo pipefail\nCFG=${a}|" \
      "$R/hpc_deploy/pswap_train.slurm" > "$R/hpc_deploy/jobs/${a}.slurm"
  o=$(sbatch "$R/hpc_deploy/jobs/${a}.slurm" 2>&1)
  j=$(echo "$o" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -z "$j" ]; then echo "SUBMIT_FAILED $a :: $o"; else echo "$a -> $j"; echo "$j" >> "$R/logs/job_ids.txt"; fi
done
echo "job ids: $(tr '\n' ' ' < $R/logs/job_ids.txt)"
squeue -u "$USER" -o '%.11i %.24j %.9T %.16E %.20R' 2>&1 | grep -Ei 'pswap|JOBID' || echo '  (none)'
echo "=== DONE ==="
