set -o pipefail
# READ-ONLY (seq 738): confirm N22-warmpair2 arm 0 got past the entry gate
sleep 180
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
squeue -u sunyiq -h -o '%.14i %.16j %.9T %.10M %R' | grep -E 'N22-warmpair2' || echo "not in queue"
sacct -X -n -P -j 242758 --format=JobID,State,ExitCode,Elapsed,NodeList
grep -hE '^#SBATCH --(output|error)' "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm"
for F in $(ls -t "$ROOT"/closure_20260810/logs/*242758* "$ROOT"/logs/*242758* 2>/dev/null | head -4); do echo "--- $F"; tail -n 15 "$F" | cut -c1-220; done
exit 0
