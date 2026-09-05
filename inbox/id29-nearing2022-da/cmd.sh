set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
echo "=== warmpair slurm header ==="
sed -n '1,40p' src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm 2>/dev/null || ls -1 src/29_nearing2022_da_ar/hpc/ | grep -i warm || true
echo "=== find logs mtime 09-03/09-04 ==="
find "$ROOT" -maxdepth 4 \( -name '*.out' -o -name '*.err' \) -newermt '2026-09-03' ! -newermt '2026-09-05' 2>/dev/null | head -30 || true
echo "=== home-level slurm logs ==="
find /data1/home/sunyiq -maxdepth 2 \( -name 'slurm-*' -o -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
