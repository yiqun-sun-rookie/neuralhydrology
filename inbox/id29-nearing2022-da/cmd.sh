set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== find 219423 / 220487 logs ==="
find "$ROOT" -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -20 || true
echo "=== slurm out dirs ==="
grep -nE 'output=|error=' "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm" 2>/dev/null || ls -1 "$ROOT/src/29_nearing2022_da_ar/hpc/" 2>/dev/null || true
