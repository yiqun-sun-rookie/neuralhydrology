set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== find 219423/220487 files ==="
find "$ROOT" ~/ -maxdepth 5 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
echo "=== slurm scripts dir ==="
ls -1 "$ROOT/src/29_nearing2022_da_ar/hpc/" 2>/dev/null | head -40 || true
echo "=== grep output paths in warmpair slurm ==="
grep -nE 'SBATCH.*(output|error)|^FINAL=|WORK|logs' "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm" 2>/dev/null | head -20 || echo "script name mismatch"
