set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== find 219423 anywhere under project+home(depth-limited) ==="
find $ROOT -name '*219423*' 2>/dev/null | head -20 || true
find ~ -maxdepth 3 -name '*219423*' 2>/dev/null | head -20 || true
echo "=== slurm script output paths ==="
S=$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm
ls -1 $ROOT/src/29_nearing2022_da_ar/hpc/ | grep -i warm || true
for f in $ROOT/src/29_nearing2022_da_ar/hpc/*warm*; do echo "--- $f"; head -40 "$f" || true; done
exit 0
