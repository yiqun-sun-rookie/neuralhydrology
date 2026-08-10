#!/bin/bash
set -o pipefail
cd ~/id17_film_gate || exit 1
J=201920
echo "=== SANITY: all 20 cells COMPLETED, no non-zero ExitCode ==="
echo "completed=$(sacct -j $J -X -n --format=State%12 | grep -c COMPLETED)  nonzero_exit=$(sacct -j $J -X -n --format=ExitCode%8 | grep -vc '0:0')"
echo "=== PROTOCOL CHECKS (must be 20) ==="
grep -ah "CHECK\] protocol OK" logs/17_entity_awareness_hypernet/gate_${J}_*.out 2>/dev/null | sort -u | wc -l
grep -ah "CHECK\] protocol OK" logs/17_entity_awareness_hypernet/gate_${J}_*.out 2>/dev/null | sort -u
echo "=== ERRORS ==="
grep -ahE "FATAL|Traceback|AssertionError" logs/17_entity_awareness_hypernet/gate_${J}_*.out logs/17_entity_awareness_hypernet/gate_${J}_*.err 2>/dev/null | grep -v FutureWarning | head -5
echo "=== ALL EPOCH-30 RESULTS ==="
grep -ah "RESULT\].*epoch30" logs/17_entity_awareness_hypernet/gate_${J}_*.out 2>/dev/null | sort -u
echo "=== FINAL VERDICT ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final >/dev/null 2>&1
python src/static_falsification/hpc/analyze_gate_matrix.py 2>&1 | tail -45
