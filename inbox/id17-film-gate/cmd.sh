#!/bin/bash
# Smoke test: full nh_run train->evaluate chain, both arms, 2 epochs, 20 train basins.
# Small job (1 node, 4 cpus, 1 gpu, <1h) to validate the chain before the 20-cell matrix.
set -o pipefail
cd ~/id17_film_gate || exit 1

echo "=== SUBMIT ==="
JID=$(sbatch --parsable src/static_falsification/hpc/smoke_gate.slurm 2>&1)
echo "jobid=$JID"

echo "=== WAIT (max 12 min this round) ==="
for i in $(seq 1 70); do
    ST=$(squeue -j "$JID" -h -o "%T" 2>/dev/null)
    [ $((i % 6)) -eq 0 ] && echo "t=$((i*10))s state=${ST:-gone}"
    [ -z "$ST" ] && break
    sleep 10
done

echo "=== SACCT ==="
sacct -j "$JID" -X --format=JobID%12,JobName%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== LOG (tail) ==="
tail -45 logs/17_entity_awareness_hypernet/smoke-${JID}.out 2>&1
echo "=== ERR (tail, if any) ==="
tail -15 logs/17_entity_awareness_hypernet/smoke-${JID}.err 2>&1

echo "=== TIMING LINES ==="
grep -E "TIMING|RESULT|FATAL|Error" logs/17_entity_awareness_hypernet/smoke-${JID}.out 2>&1
