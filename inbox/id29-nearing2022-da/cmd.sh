set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== search 219423/220487 log files anywhere under ROOT and ~/logs ==="
find "$ROOT" ~/logs -maxdepth 6 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -30 || true
echo "=== slurm script StdOut spec ==="
grep -nE 'output|error|SBATCH' "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm" 2>/dev/null | head -30 || echo "  slurm file not found; listing hpc dir"
ls -1 "$ROOT/src/29_nearing2022_da_ar/hpc/" 2>/dev/null || true
exit 0
