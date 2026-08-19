#!/usr/bin/env bash
# zhenjiang out-of-year validation :: step 10
# Resume watching training array 205647 and chain the evaluation. The seq 9
# worker was killed by a daemon restart and its truncated staging file was pushed
# as the result, so the runner considers seq 9 done and will not retry it; the
# chain therefore has to be re-armed here.
#
# The window is kept to sixty minutes so this reports rather than risking another
# mid-loop kill. Re-submitting the evaluation twice is harmless: the evaluation
# script refuses to write into an output root that already exists.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
JID=205647

echo "=== A. IMMEDIATE STATE ==="
echo "completed_task_dirs=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)"
echo "queue_entries=$(squeue -j "$JID" -h -o '%i' 2>/dev/null | wc -l)"
sacct -j "$JID" -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c || true

echo "=== B. WATCH TO COMPLETION (max 60 min) ==="
for i in $(seq 1 360); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    DONE=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)
    [ $((i % 30)) -eq 0 ] && echo "t=$((i * 10))s queue_entries=$LEFT completed_task_dirs=$DONE"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

DONE=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)
echo "=== C. FINAL TRAINING STATE ==="
echo "completed_task_dirs=$DONE"
sacct -j "$JID" -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c || true
echo "--- any task that did not complete ---"
sacct -j "$JID" -X --format=JobID%16,NodeList%9,State%14,ExitCode%8,Elapsed%10 --noheader 2>/dev/null \
    | grep -v COMPLETED | head -20 || true

echo "=== D. NODE AND ENVIRONMENT SPREAD ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null || echo "CONDA_ACTIVATE_FAILED"
PYTHONPATH="$ROOT/pysite" python - "$ROOT/tasks" <<'PY'
import json
from collections import Counter
from pathlib import Path
import sys
nodes, cards, tp, elapsed, epochs = Counter(), Counter(), Counter(), [], []
for path in sorted(Path(sys.argv[1]).glob("*/run_identity.json")):
    d = json.loads(path.read_text(encoding="utf-8"))
    env = d.get("runtime_environment", {})
    nodes[env.get("node_name")] += 1
    cards[env.get("graphics_processor_unique_identifier")] += 1
    tp[env.get("normalised_threadpool_configuration_sha256")] += 1
    elapsed.append(float(d.get("elapsed_seconds", 0.0)))
    epochs.append(int(d.get("completed_epochs", 0)))
elapsed.sort(); epochs.sort()
def q(v, f):
    return round(v[int(len(v) * f)], 1) if v else None
print(json.dumps({
    "identities_read": sum(nodes.values()),
    "nodes": dict(nodes),
    "distinct_cards": len(cards),
    "distinct_normalised_threadpool_digests": list(tp),
    "elapsed_seconds": {"min": q(elapsed, 0), "median": q(elapsed, 0.5), "max": elapsed[-1] if elapsed else None},
    "completed_epochs": {"min": epochs[0] if epochs else None, "median": q(epochs, 0.5), "max": epochs[-1] if epochs else None},
    "total_gpu_hours": round(sum(elapsed) / 3600.0, 2),
}, indent=2, sort_keys=True))
PY

if [ "$DONE" -ne 480 ]; then
    echo "=== E. NOT 480 YET, NOT CHAINING ==="
    echo "=== END ==="
    exit 0
fi

echo "=== E. SUBMIT EVALUATION AND INFERENCE ==="
cd "$ROOT/repo" || exit 1
EJ=$(sbatch --parsable scripts/analysis/hpc/submit_evaluate_and_infer.slurm 2>&1)
echo "evaluation_job=$EJ"
case "$EJ" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac
for i in $(seq 1 150); do
    LEFT=$(squeue -j "$EJ" -h -o "%i" 2>/dev/null | wc -l)
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done
sacct -j "$EJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
echo "--- evaluation and inference log ---"
tail -60 "$ROOT/logs/evaluate_${EJ}.out" 2>/dev/null || true
echo "--- stderr tail ---"
tail -15 "$ROOT/logs/evaluate_${EJ}.err" 2>/dev/null || true
echo "=== END ==="
