set -o pipefail
cd /data1/home/sunyiq/nearing2022_da
echo "=== find warmpair/replv2 slurm logs ==="
find . -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -20 || true
echo "=== slurm script paths ==="
ls -1 src/29_nearing2022_da_ar/hpc/ 2>/dev/null | grep -Ei 'warm|repl' || echo '  none'
echo "=== output path directive in warmup slurm ==="
grep -E '^#SBATCH' src/29_nearing2022_da_ar/hpc/train_warmup_target_pair.slurm 2>/dev/null || grep -rlE 'warmup_pair' src/29_nearing2022_da_ar/hpc/ 2>/dev/null || echo '  not found'
