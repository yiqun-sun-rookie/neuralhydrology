set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== SLURM SCRIPT SBATCH HEADER ==="
sed -n '1,40p' $ROOT/src/29_nearing2022_da_ar/hpc/*warmup*pair*.slurm 2>/dev/null || ls -1 $ROOT/src/29_nearing2022_da_ar/hpc/ 2>/dev/null || true
echo "=== FIND 219423 LOGS ANYWHERE ==="
find $ROOT -maxdepth 4 -name '*219423*' 2>/dev/null | head -20 || true
find ~ -maxdepth 2 -name '*219423*' 2>/dev/null | head -20 || true
echo "=== FIND 220487 ==="
find $ROOT -maxdepth 4 -name '*220487*' 2>/dev/null | head -10 || true
echo "=== sacct detail ==="
sacct -j 219423 -P -n --format=JobID,JobName,State,ExitCode,WorkDir%120 2>/dev/null | head -10 || true
exit 0
