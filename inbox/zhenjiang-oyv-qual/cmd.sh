#!/usr/bin/env bash
# zhenjiang out-of-year validation :: step 11
# Training finished 480 of 480. The evaluation submission failed only because the
# cluster clone predates the commit that added the analysis batch jobs, so update
# the clone first, re-verify the digest chain, then run evaluation and inference.
#
# Updating the clone cannot disturb the training artifacts: they live outside the
# repository, under tasks/, and the newer commit only adds files.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. UPDATE CLONE ==="
cd "$ROOT/repo" || { echo "REPO_MISSING"; exit 1; }
echo "commit_before=$(git rev-parse HEAD)"
timeout 600 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -3
timeout 120 git reset -q --hard refs/remotes/origin/main
echo "commit_after=$(git rev-parse HEAD)"
test -f scripts/analysis/hpc/submit_evaluate_and_infer.slurm && echo "evaluate_slurm_present=true" || echo "evaluate_slurm_present=false"
test -f scripts/analysis/hpc/submit_independent_audit.slurm && echo "audit_slurm_present=true" || echo "audit_slurm_present=false"
echo "task_dirs=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)"

echo "=== B. DIGEST CHAIN AFTER UPDATE ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final || { echo "CONDA_ACTIVATE_FAILED"; exit 1; }
PYTHONPATH="$ROOT/pysite" python - "$ROOT/repo" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
reg = json.loads((root / "docs/records/ZHENJIANG_OYV_LEAVE_ONE_YEAR_OUT_DIRECTION_VALIDATION_V1_REGISTRY.json").read_bytes().decode("utf-8"))
def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "absent"
src_bad = [r for r, e in reg["source_identities"].items() if digest(root / r) != e["sha256"]]
base = root / "data/processed/water_level_model_input_v7_beijing_realtime_verified"
in_bad = [r for r, e in reg["input_identities"].items() if digest(base / r) != e["sha256"]]
print(json.dumps({"source_files": len(reg["source_identities"]), "source_mismatched": len(src_bad), "source_bad": src_bad,
                  "input_files": len(reg["input_identities"]), "input_mismatched": len(in_bad)}, indent=2, sort_keys=True))
PY

echo "=== C. SUBMIT EVALUATION AND INFERENCE ==="
EJ=$(sbatch --parsable scripts/analysis/hpc/submit_evaluate_and_infer.slurm 2>&1)
echo "evaluation_job=$EJ"
case "$EJ" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac
for i in $(seq 1 200); do
    LEFT=$(squeue -j "$EJ" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 30)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done
sacct -j "$EJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4

echo "=== D. EVALUATION AND INFERENCE OUTPUT ==="
tail -70 "$ROOT/logs/evaluate_${EJ}.out" 2>/dev/null || true
echo "--- stderr tail ---"
tail -15 "$ROOT/logs/evaluate_${EJ}.err" 2>/dev/null || true

echo "=== E. CONFIRMATORY TESTS ==="
cat "$ROOT/inference/confirmatory_tests.csv" 2>/dev/null || true
echo "--- fold year medians ---"
cat "$ROOT/inference/fold_year_medians.csv" 2>/dev/null || true
echo "=== END ==="
