set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
echo "=== SLURM SCRIPT OUTPUT DIRECTIVES ==="
grep -nE '^#SBATCH (--output|--error|-o |-e )' src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm 2>/dev/null || echo 'script not found by that name'
ls -1 src/29_nearing2022_da_ar/hpc/ 2>/dev/null | grep -iE 'warm|repl' || true
echo "=== FIND LOGS ANYWHERE ==="
find "$ROOT" -maxdepth 4 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
echo "=== HOME LOGS ==="
find ~ -maxdepth 3 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
exit 0
