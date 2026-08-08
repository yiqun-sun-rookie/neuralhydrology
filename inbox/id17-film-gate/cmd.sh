#!/bin/bash
set -o pipefail
cd ~/id17_film_gate || exit 1
J=201920
echo "=== QUEUE ==="
echo "running=$(squeue -j $J -h -t R 2>/dev/null | wc -l) pending=$(squeue -j $J -h -t PD 2>/dev/null | wc -l)"
squeue -j $J -h -o "%.16i %.8T %.10M %R" 2>&1 | head -10
echo "=== FINISHED CELLS (sacct) ==="
sacct -j $J -X --format=JobID%18,State%12,ExitCode%8,Elapsed%11 2>&1 | grep -vE "^ *JobID|^-" | head -25
echo "=== RESULTS SO FAR ==="
grep -ah "RESULT\]" logs/17_entity_awareness_hypernet/gate_${J}_*.out 2>/dev/null | sort -u
echo "=== PROTOCOL CHECKS ==="
grep -ah "CHECK\]" logs/17_entity_awareness_hypernet/gate_${J}_*.out 2>/dev/null | sort -u | head -5
echo "=== ERRORS ==="
grep -ahE "FATAL|Traceback|AssertionError" logs/17_entity_awareness_hypernet/gate_${J}_*.out logs/17_entity_awareness_hypernet/gate_${J}_*.err 2>/dev/null | grep -v FutureWarning | head -6
echo "=== PROGRESS (latest epoch per running cell) ==="
for f in logs/17_entity_awareness_hypernet/gate_${J}_*.out; do
  E=$(grep -ao "Epoch [0-9]* average loss" "$f" 2>/dev/null | tail -1)
  [ -n "$E" ] && echo "$(basename $f): $E"
done | head -10
