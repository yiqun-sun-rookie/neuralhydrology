set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== SLURM SCRIPT OUTPUT DIRECTIVES ==="
grep -nE '^#SBATCH (--output|--error|-o |-e )' "$ROOT/src/29_nearing2022_da_ar/hpc/"*warmup*.slurm 2>/dev/null || echo none
echo "=== SLURM SCRIPTS PRESENT ==="
ls -1 "$ROOT/src/29_nearing2022_da_ar/hpc/" 2>/dev/null | head -40 || true
echo "=== FIND 219423 FILES UNDER ROOT (depth 5) ==="
find "$ROOT" -maxdepth 5 -name '*219423*' 2>/dev/null | head -20 || true
find "$HOME" -maxdepth 2 -name '*219423*' 2>/dev/null | head -20 || true
exit 0
