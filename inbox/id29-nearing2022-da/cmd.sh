set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== slurm script SBATCH headers ==="
sed -n '1,30p' "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm" 2>/dev/null || ls "$ROOT/src/29_nearing2022_da_ar/hpc/" | grep -i warm || true
echo "=== search whole home for 219423 logs ==="
find "$ROOT" -maxdepth 5 -name '*219423*' 2>/dev/null | head -20 || true
find ~/ -maxdepth 2 -name '*219423*' 2>/dev/null | head -20 || true
echo "=== 220487 ==="
find "$ROOT" -maxdepth 5 -name '*220487*' 2>/dev/null | head -20 || true
