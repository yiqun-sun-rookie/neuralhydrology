set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== SBATCH DIRECTIVES ==="
grep -E '^#SBATCH' "$ROOT/src/29_nearing2022_da_ar/hpc/train_warmup_target_pair.slurm" 2>/dev/null || ls "$ROOT/src/29_nearing2022_da_ar/hpc/" 2>/dev/null || true
echo "=== SEARCH WHOLE ROOT FOR 219423 LOGS ==="
find "$ROOT" -maxdepth 5 -name '*219423*' 2>/dev/null | head -20 || true
find ~ -maxdepth 3 -name '*219423*' 2>/dev/null | head -20 || true
echo "=== 220487 ==="
find "$ROOT" ~ -maxdepth 4 -name '*220487*' 2>/dev/null | head -10 || true
exit 0
