#!/bin/bash
# attrswap-daily seq=2 -- deploy the isolated landing dir and submit the 7 arms (parity gate first, 6 afterok dependents).
# Writes ONLY under /data1/home/sunyiq/attr_swap_daily_2026_09. Read-only on ~/neuralhydrology (git archive + symlinked data).
set -o pipefail
ROOT=/data1/home/sunyiq/attr_swap_daily_2026_09
SRC=/data1/home/sunyiq/hpc_mailbox/inbox/attrswap-daily/payload
NH=/data1/home/sunyiq/neuralhydrology
D=$NH/data/camels_us
COMMIT=1f9804e359283f1963bcf0aa9ffab213538c16e8
PARITY=attrswap_ref27_parity_s900
ARMS="attrswap_armA_chn23_s100 attrswap_armA_chn23_s200 attrswap_armA_chn23_s300 attrswap_armB_drop23_s100 attrswap_armB_drop23_s200 attrswap_armB_drop23_s300"
date "+wallclock %F %T %z"; hostname

echo "=== 0. GUARDS ==="
if [ -d "$ROOT/runs" ] && [ -n "$(ls -A "$ROOT/runs" 2>/dev/null)" ]; then echo "ROOT/runs not empty -- refusing to redeploy"; exit 1; fi
if squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -q '^attrswap_'; then echo "attrswap_* jobs already queued -- refusing"; exit 1; fi
[ -d "$SRC/configs" ] || { echo "PAYLOAD MISSING at $SRC"; exit 1; }

echo "=== 1. CODE: git archive $COMMIT (read-only on the repo) ==="
mkdir -p "$ROOT/code_1f9804e" "$ROOT/logs" "$ROOT/runs" "$ROOT/configs" "$ROOT/basin_lists" "$ROOT/data_shadow/camels_us/camels_attributes_v2.0"
if ( cd "$NH" && git cat-file -e "$COMMIT" 2>/dev/null ); then
  ( cd "$NH" && git archive --format=tar "$COMMIT" neuralhydrology setup.py setup.cfg ) | tar -x -C "$ROOT/code_1f9804e" && echo "archived from repo"
else
  echo "commit not in ~/neuralhydrology -> using payload tarball"; tar -xzf "$SRC/code_1f9804e.tar.gz" -C "$ROOT/code_1f9804e"
fi
( cd "$ROOT/code_1f9804e" && sha256sum -c --quiet "$SRC/code_manifest.sha256" && echo "CODE MANIFEST OK ($(wc -l < "$SRC/code_manifest.sha256") files byte-identical to local archive)" ) || echo "CODE MANIFEST MISMATCH"
echo "camelsus.py $(sha256sum "$ROOT/code_1f9804e/neuralhydrology/datasetzoo/camelsus.py" | cut -c1-16)"

echo "=== 2. DATA SHADOW (streamflow dir symlinked; maurer per-file symlinks + 4 header-fixed copies; attributes copied + chnsupply) ==="
ln -sfn "$D/usgs_streamflow" "$ROOT/data_shadow/camels_us/usgs_streamflow"
mkdir -p "$ROOT/data_shadow/camels_us/basin_mean_forcing"
for sub in daymet nldas; do [ -d "$D/basin_mean_forcing/$sub" ] && ln -sfn "$D/basin_mean_forcing/$sub" "$ROOT/data_shadow/camels_us/basin_mean_forcing/$sub"; done
NHPY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python; [ -x "$NHPY" ] || NHPY=python3
"$NHPY" "$SRC/hpc_fix_maurer_headers.py" "$D/basin_mean_forcing/maurer" "$ROOT/data_shadow/camels_us/basin_mean_forcing/maurer" 2>&1 | tail -30
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "MAURER SHADOW VERIFICATION FAILED -- not submitting"; exit 1; }
for a in clim geol hydro name soil topo vege; do cp "$D/camels_attributes_v2.0/camels_${a}.txt" "$ROOT/data_shadow/camels_us/camels_attributes_v2.0/"; done
cp "$SRC/camels_chnsupply.txt" "$ROOT/data_shadow/camels_us/camels_attributes_v2.0/"
ls "$ROOT/data_shadow/camels_us/camels_attributes_v2.0/" | tr '\n' ' '; echo
echo "chnsupply $(sha256sum "$ROOT/data_shadow/camels_us/camels_attributes_v2.0/camels_chnsupply.txt" | cut -c1-16) lines=$(wc -l < "$ROOT/data_shadow/camels_us/camels_attributes_v2.0/camels_chnsupply.txt") (local LF hash bb6ee2e36f23182d, 530 lines)"
echo "maurer_files=$(find "$ROOT/data_shadow/camels_us/basin_mean_forcing/maurer/" -type f | wc -l) streamflow_files=$(find "$ROOT/data_shadow/camels_us/usgs_streamflow/" -type f | wc -l)"

echo "=== 3. CONFIGS / LISTS / SCRIPTS ==="
cp "$SRC"/configs/*.yml "$ROOT/configs/"; cp "$SRC"/basin_lists/*.txt "$ROOT/basin_lists/"
cp "$SRC/hpc_gate_median.py" "$SRC/attrswap_arm.slurm" "$ROOT/"
sed -i 's/\r$//' "$ROOT/attrswap_arm.slurm" "$ROOT/hpc_gate_median.py"
( cd "$ROOT" && sha256sum configs/*.yml basin_lists/*.txt hpc_gate_median.py attrswap_arm.slurm | sed 's/^\(.\{16\}\)[0-9a-f]*  /\1  /' )
echo "basins_529 lines=$(wc -l < "$ROOT/basin_lists/basins_529.txt") holdout lines=$(wc -l < "$ROOT/basin_lists/holdout_107.txt")"
grep -c '^- ' "$ROOT/configs/attrswap_armA_chn23_s100.yml" | sed 's/^/list items in armA s100 config: /'

echo "=== 4. SUBMIT parity (gate) ==="
cd "$ROOT" || exit 1
sed 's/^__DEPENDENCY_LINE__$//' attrswap_arm.slurm > "job_${PARITY}.slurm"
out=$(sbatch --job-name="$PARITY" --export=ALL,ARM="$PARITY" "job_${PARITY}.slurm" 2>&1); echo "$out" | head -3
PJ=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$PJ" ] || { echo "SUBMIT_FAILED parity"; exit 1; }
echo "parity $PJ" > logs/job_ids.txt

echo "=== 5. SUBMIT 6 arms (afterok:$PJ) ==="
for ARM in $ARMS; do
  sed "s/^__DEPENDENCY_LINE__$/#SBATCH --dependency=afterok:$PJ/" attrswap_arm.slurm > "job_${ARM}.slurm"
  out=$(sbatch --job-name="$ARM" --export=ALL,ARM="$ARM" "job_${ARM}.slurm" 2>&1)
  J=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -n "$J" ]; then echo "$ARM job=$J"; echo "$ARM $J" >> logs/job_ids.txt; else echo "SUBMIT_FAILED $ARM: $(echo "$out" | head -2)"; fi
done

echo "=== 6. QUEUE ==="
squeue -u "$USER" -h -o '%.11i %.28j %.9T %.10M %.9N %.8P %.24E' 2>&1 | grep attrswap || echo "(none visible)"
echo "=== DONE ==="
