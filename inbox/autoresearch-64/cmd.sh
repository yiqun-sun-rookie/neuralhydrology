#!/bin/bash
set -eo pipefail

echo "=== SUBMIT EIGHT-BASIN HBV-LITE SMOKE ==="
JID=$(sbatch --parsable inbox/autoresearch-64/hbv_lite_8_smoke_seq36.slurm)
echo "jobid=$JID"
echo "=== INITIAL STATE ==="
squeue -j "$JID" -h -o 'job=%i state=%T elapsed=%M node=%N'
sacct -j "$JID" -X --format=JobID%12,JobName%20,State%14,ExitCode%8,Elapsed%10
