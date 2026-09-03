set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
S=$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm
ls -1 $ROOT/src/29_nearing2022_da_ar/hpc/ | grep -i warm || true
echo "=== SBATCH HEADER ==="
[ -f "$S" ] && head -40 "$S" || echo "script name differs"
echo "=== SEARCH LOGS TREE ==="
find $ROOT -maxdepth 4 -name '*219423*' 2>/dev/null | head -20 || true
find /data1/home/sunyiq/logs -name '*219423*' 2>/dev/null | head -20 || true
exit 0
