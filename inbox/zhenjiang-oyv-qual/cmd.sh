#!/usr/bin/env bash
# zhenjiang out-of-year validation :: step 9
# Watch training array 205647 to completion, then chain the evaluation and the
# registered inference. Only waits and submits; computes nothing on this node.
# Capped below the mailbox worker timeout so a long run reports rather than dies.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
JID=205647

echo "=== A. WATCH TRAINING ARRAY (max 100 min) ==="
for i in $(seq 1 600); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    DONE=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)
    [ $((i % 60)) -eq 0 ] && echo "t=$((i * 10))s queue_entries=$LEFT completed_task_dirs=$DONE"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

DONE=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)
echo "=== B. TRAINING STATE ==="
echo "completed_task_dirs=$DONE"
sacct -j "$JID" -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c || true
echo "--- non completed tasks, if any ---"
sacct -j "$JID" -X --format=JobID%16,NodeList%9,State%14,ExitCode%8,Elapsed%10 --noheader 2>/dev/null \
    | grep -v COMPLETED | head -20 || true

echo "=== C. NODE AND ENVIRONMENT SPREAD ==="
PYTHONPATH="$ROOT/pysite" python - "$ROOT/tasks" <<'PY'
import json
from collections import Counter
from pathlib import Path
import sys
nodes, cards, norm_tp, elapsed = Counter(), Counter(), Counter(), []
for path in sorted(Path(sys.argv[1]).glob("*/run_identity.json")):
    d = json.loads(path.read_text(encoding="utf-8"))
    env = d.get("runtime_environment", {})
    nodes[env.get("node_name")] += 1
    cards[env.get("graphics_processor_unique_identifier")] += 1
    norm_tp[env.get("normalised_threadpool_configuration_sha256")] += 1
    elapsed.append(d.get("elapsed_seconds", 0.0))
elapsed.sort()
print(json.dumps({
    "task_identities_read": sum(nodes.values()),
    "nodes": dict(nodes),
    "distinct_cards": len(cards),
    "distinct_normalised_threadpool_digests": list(norm_tp),
    "elapsed_seconds_min": round(elapsed[0], 1) if elapsed else None,
    "elapsed_seconds_median": round(elapsed[len(elapsed)//2], 1) if elapsed else None,
    "elapsed_seconds_max": round(elapsed[-1], 1) if elapsed else None,
}, indent=2, sort_keys=True))
PY

if [ "$DONE" -ne 480 ]; then
    echo "=== D. NOT ALL 480 TASKS PRESENT, NOT CHAINING ==="
    echo "END"
    exit 0
fi

echo "=== D. SUBMIT EVALUATION AND INFERENCE ==="
cd "$ROOT/repo" || exit 1
EJ=$(sbatch --parsable scripts/analysis/hpc/submit_evaluate_and_infer.slurm 2>&1)
echo "evaluation_job=$EJ"
case "$EJ" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac
for i in $(seq 1 180); do
    LEFT=$(squeue -j "$EJ" -h -o "%i" 2>/dev/null | wc -l)
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done
sacct -j "$EJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
echo "--- evaluation log tail ---"
tail -45 "$ROOT/logs/evaluate_${EJ}.out" 2>/dev/null || true
echo "--- stderr tail ---"
tail -15 "$ROOT/logs/evaluate_${EJ}.err" 2>/dev/null || true
echo "=== END ==="
