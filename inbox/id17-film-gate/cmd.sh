#!/bin/bash
# Pull the smoke-config fix, rerun the smoke test (validates FiLM arm + evaluate + assertions).
set -o pipefail
cd ~/id17_film_gate || exit 1

echo "=== A. UPDATE CODE ==="
git fetch -q origin "+hpc/id17-film-gate:refs/remotes/origin/hpc/id17-film-gate" 2>&1 | tail -1
git reset -q --hard refs/remotes/origin/hpc/id17-film-gate
git log --oneline -1
sed -i 's/\r$//' src/static_falsification/hpc/*.slurm
rm -rf runs/smoke_* 2>/dev/null

echo "=== B. SUBMIT SMOKE ==="
JID=$(sbatch --parsable src/static_falsification/hpc/smoke_gate.slurm 2>&1)
echo "jobid=$JID"

echo "=== C. WAIT (max 13 min) ==="
for i in $(seq 1 78); do
    ST=$(squeue -j "$JID" -h -o "%T" 2>/dev/null)
    [ $((i % 12)) -eq 0 ] && echo "t=$((i*10))s state=${ST:-gone}"
    [ -z "$ST" ] && break
    sleep 10
done

echo "=== D. SACCT ==="
sacct -j "$JID" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== E. KEY LINES ==="
grep -aE "TIMING|RESULT|FATAL|INFO\] torch|SMOKE DONE" logs/17_entity_awareness_hypernet/smoke-${JID}.out 2>&1
echo "--- errors (if any) ---"
grep -aE "Traceback|Error|error:" logs/17_entity_awareness_hypernet/smoke-${JID}.out 2>&1 | grep -v FutureWarning | head -8
