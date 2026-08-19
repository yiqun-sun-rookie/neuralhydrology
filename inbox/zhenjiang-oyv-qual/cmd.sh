#!/usr/bin/env bash
# zhenjiang out-of-year validation :: step 12, independent audit
# The registered inference returned NOT_CONFIRMED. That verdict is only worth
# reporting once it has been independently reproduced, so this submits the audit
# that re-derives the partitions, the direction rule, the events, the errors and
# the statistics, and re-runs inference from every checkpoint for a bitwise
# comparison against the stored packages.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. EVALUATION SUMMARY ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null || echo "CONDA_ACTIVATE_FAILED"
PYTHONPATH="$ROOT/pysite" python - "$ROOT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
s = json.loads((root / "evaluation/evaluation_summary.json").read_text(encoding="utf-8"))
keep = ("task_count_expected", "task_count_read", "paired_event_count", "paired_event_indices",
        "minimum_paired_event_count", "coverage_gate_passed", "fold_years_with_paired_events",
        "event_count_total", "primary_horizon_hours")
print(json.dumps({k: s[k] for k in keep if k in s}, indent=2, sort_keys=True))
PY
echo "--- artifact manifests ---"
cat "$ROOT/evaluation/completion_manifest.json" 2>/dev/null | head -30 || true
cat "$ROOT/inference/completion_manifest.json" 2>/dev/null | head -30 || true

echo "=== B. SUBMIT INDEPENDENT AUDIT ==="
cd "$ROOT/repo" || exit 1
AJ=$(sbatch --parsable scripts/analysis/hpc/submit_independent_audit.slurm 2>&1)
echo "independent_audit_job=$AJ"
case "$AJ" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac

echo "=== C. WAIT (max 95 min) ==="
for i in $(seq 1 570); do
    LEFT=$(squeue -j "$AJ" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 60)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== D. AUDIT RESULT ==="
sacct -j "$AJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
cat "$ROOT/independent_audit/independent_audit_summary.json" 2>/dev/null || true
echo "--- mismatches, first lines ---"
head -20 "$ROOT/independent_audit/mismatches.csv" 2>/dev/null || true
echo "--- audit log tail ---"
tail -25 "$ROOT/logs/independent_audit_${AJ}.out" 2>/dev/null || true
echo "--- stderr tail ---"
tail -20 "$ROOT/logs/independent_audit_${AJ}.err" 2>/dev/null || true
echo "=== END ==="
