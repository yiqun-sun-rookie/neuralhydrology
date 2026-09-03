#!/bin/bash
# Submit the parameter-axis open-loop probe (CPU only), wait, report.
set -o pipefail
ROOT=/data1/home/sunyiq/id23_param_probe
cd "$ROOT" || exit 1

echo "=== SUBMIT ==="
JID=$(sbatch --parsable par_probe.slurm 2>&1)
echo "jobid=$JID"
# Run manifest: the ONLY job ids this line may ever cancel individually.
printf '%s\t%s\tpar_probe_v01\n' "$(date -Iseconds)" "$JID" >> "$ROOT/run_manifest.tsv"
squeue -j "$JID" -o "%.10i %.16j %.10P %.8T %R" 2>&1 | head -4

echo "=== WAIT (max 10 min) ==="
for i in $(seq 1 60); do
    STATE=$(squeue -j "$JID" -h -o "%T" 2>/dev/null)
    [ -z "$STATE" ] && { echo "t=${i}0s finished"; break; }
    [ $((i % 3)) -eq 0 ] && echo "t=${i}0s state=$STATE"
    sleep 10
done

echo "=== ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%14,Partition%9,NodeList%9,State%12,ExitCode%8,Elapsed%10,MaxRSS%10,AllocTRES%28 2>&1 | head -6

echo "=== JOB LOG ==="
tail -60 "$ROOT/logs/par_probe_${JID}.out" 2>&1
echo "=== STDERR (if any) ==="
tail -15 "$ROOT/logs/par_probe_${JID}.err" 2>&1

echo "=== OUTPUT FILES ==="
ls -la "$ROOT/out" 2>&1
