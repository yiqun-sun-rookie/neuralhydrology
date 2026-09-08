#!/bin/bash
# forcing-swap seq=12 -- deploy the isolated landing dir, generate 9+1 configs, submit gate + 9 arms (afterok).
# Login node does only file copies and submission; all reading of the 529 netCDFs happens inside the gate job.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09
A=/data1/home/sunyiq/attr_swap_daily_2026_09
M=$HOME/hpc_mailbox/inbox/attrswap-daily/payload

echo "=== A. LANDING DIR ==="
[ -d "$R" ] && { echo "LANDING ALREADY EXISTS -- refusing to redeploy"; ls "$R"; exit 1; }
mkdir -p "$R"/{logs,runs,runs_smoke,configs,basin_lists,hpc_deploy/jobs,data_shadow/camels_us/basin_mean_forcing}
echo "created $R"

echo "=== B. CODE (copied from the already-verified attr-swap landing) ==="
cp -r "$A/code_1f9804e" "$R/" || { echo CODE_COPY_FAILED; exit 1; }
nfiles=$(find "$R/code_1f9804e" -type f | wc -l)
csha=$(sha256sum "$R/code_1f9804e/neuralhydrology/datasetzoo/camelsus.py" | cut -c1-16)
echo "code files: $nfiles (expect 142); camelsus.py sha: $csha (expect 51e2e02b382ec103)"
[ "$nfiles" = "142" ] && [ "$csha" = "51e2e02b382ec103" ] || { echo CODE_VERIFY_FAILED; exit 1; }

echo "=== C. DATA SHADOW (streamflow / attributes / maurer all reference the verified attr-swap shadow) ==="
ln -s "$A/data_shadow/camels_us/usgs_streamflow" "$R/data_shadow/camels_us/usgs_streamflow"
ln -s "$A/data_shadow/camels_us/camels_attributes_v2.0" "$R/data_shadow/camels_us/camels_attributes_v2.0"
ln -s "$A/data_shadow/camels_us/basin_mean_forcing/maurer" "$R/data_shadow/camels_us/basin_mean_forcing/maurer"
ls -la "$R/data_shadow/camels_us" "$R/data_shadow/camels_us/basin_mean_forcing"
echo "maurer files visible: $(find -L "$R/data_shadow/camels_us/basin_mean_forcing/maurer" -name '*_forcing_leap.txt' | wc -l) (expect 675)"
echo "attribute files visible: $(ls -L "$R/data_shadow/camels_us/camels_attributes_v2.0" | wc -l) (expect 8)"

echo "=== D. BASIN LISTS + MEDIAN SCRIPT ==="
cp "$A/basin_lists/basins_529.txt" "$A/basin_lists/holdout_107.txt" "$R/basin_lists/"
head -5 "$R/basin_lists/basins_529.txt" > "$R/basin_lists/basins_5.txt"
cp "$A/scripts_public_median.py" "$R/"
echo "529: $(wc -l < $R/basin_lists/basins_529.txt)  107: $(wc -l < $R/basin_lists/holdout_107.txt)  smoke: $(wc -l < $R/basin_lists/basins_5.txt)"
sha_b=$(sha256sum "$R/basin_lists/basins_529.txt" | cut -c1-16); echo "basins_529 sha: $sha_b (expect 98018c03b0295a56)"
[ "$sha_b" = "98018c03b0295a56" ] || { echo BASIN_LIST_MISMATCH; exit 1; }

echo "=== E. PAYLOAD ==="
cp "$M"/build_era5l_forcing.py "$M"/make_configs.py "$M"/fswap_gate.slurm "$M"/fswap_train.slurm "$R/hpc_deploy/" \
  || { echo PAYLOAD_COPY_FAILED; exit 1; }
sed -i 's/\r$//' "$R"/hpc_deploy/*.py "$R"/hpc_deploy/*.slurm
for f in "$R"/hpc_deploy/*; do [ -f "$f" ] && echo "  $(basename $f) $(sha256sum $f | cut -c1-16) $(wc -l < $f) lines"; done

echo "=== F. CONFIGS ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python -u "$R/hpc_deploy/make_configs.py" || { echo CONFIG_GEN_FAILED; exit 1; }
ls "$R/configs"
echo "--- diff of one arm vs its base (should be only the allowed lines) ---"
diff "$A/configs/attrswap_ref27_parity_s900.yml" "$R/configs/fswap_armE27_s100.yml"
echo "--- armE23 attribute count ---"
python -u -c "
import yaml
c = yaml.safe_load(open('$R/configs/fswap_armE23_s100.yml'))
d = yaml.safe_load(open('$R/configs/fswap_armE27_s100.yml'))
print('armE23 static attrs:', len(c['static_attributes']), '| armE27:', len(d['static_attributes']))
print('armE23 forcings:', c['forcings'], '| dynamic_inputs:', c['dynamic_inputs'])
print('epochs', c['epochs'], 'seq_length', c['seq_length'], 'hidden', c.get('hidden_size'), 'train', c['train_start_date'], c['train_end_date'], 'test', c['test_start_date'], c['test_end_date'])
"

echo "=== G. SUBMIT GATE ==="
out=$(sbatch "$R/hpc_deploy/fswap_gate.slurm" 2>&1); echo "$out"
GATE=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$GATE" ] || { echo SUBMIT_FAILED_GATE; exit 1; }
echo "gate job: $GATE"

echo "=== H. SUBMIT 9 ARMS (afterok:$GATE, dependency baked into each script) ==="
echo "$GATE" > "$R/logs/job_ids.txt"
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

echo "=== I. QUEUE ==="
squeue -u "$USER" -o '%.11i %.22j %.9T %.10M %.9N %.9P %.22E' 2>&1 | grep -Ei 'fswap|JOBID' || echo '  (none)'
echo "=== DONE ==="
