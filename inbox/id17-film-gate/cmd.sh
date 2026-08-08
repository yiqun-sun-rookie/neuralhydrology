#!/bin/bash
set -o pipefail
cd ~/id17_film_gate || exit 1
JID=201892
echo "=== SACCT ==="
sacct -j "$JID" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1
echo "=== KEY LINES ==="
grep -aE "TIMING|RESULT|FATAL|CHECK|SMOKE DONE" logs/17_entity_awareness_hypernet/smoke-${JID}.out 2>&1
echo "=== ERRORS ==="
grep -aE "Traceback|Error|error:" logs/17_entity_awareness_hypernet/smoke-${JID}.out 2>&1 | grep -v FutureWarning | head -8
echo "=== RUNS PRODUCED ==="
ls -d runs/smoke_* 2>&1
for d in runs/smoke_*; do echo "$d: $(ls $d/model_epoch*.pt 2>/dev/null | wc -l) ckpts, test dirs: $(ls -d $d/test/* 2>/dev/null | wc -l)"; done
