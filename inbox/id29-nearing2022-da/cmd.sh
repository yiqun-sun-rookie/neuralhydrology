set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== slurm script header ==="
sed -n '1,40p' $ROOT/src/29_nearing2022_da_ar/hpc/warmup_target_pair.slurm 2>/dev/null || ls -1 $ROOT/src/29_nearing2022_da_ar/hpc/ 2>/dev/null
echo "=== find recent log files ==="
find $ROOT -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -20 || true
echo "=== logs dir tops ==="
ls -1t /data1/home/sunyiq/nearing2022_da/logs 2>/dev/null | head -20 || echo nologs
ls -1t ~/logs 2>/dev/null | head -20 || true
echo "=== newest files under ROOT modified since 09-03 ==="
find $ROOT -maxdepth 5 -newermt '2026-09-03' -name '*.err' 2>/dev/null | head -20 || true
exit 0
