#!/usr/bin/env bash
# zhenjiang gauge failure study :: repair the clone, then audit the ladder
#
# Commit b0c7ab9 accidentally deleted 52 files from the bundle: the station data,
# the frozen tide model with its thirty verified dependencies, and three frozen
# source modules. The cause was the bundle worktree sitting in a Windows temp
# directory that the operating system cleaned. e96bec7 restores every one of them
# byte for byte from the last commit that had them.
#
# The cluster clone was reset to the damaged commit by the previous round, so it
# has to be repaired before anything can run. Nothing under tasks/ or
# ladder_tasks/ was ever at risk: those live outside the repository.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. REPAIR THE CLONE ==="
cd "$ROOT/repo" || { echo "REPO_MISSING"; exit 1; }
echo "commit_before=$(git rev-parse --short HEAD)"
timeout 900 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -2
timeout 300 git reset -q --hard refs/remotes/origin/main
echo "commit_after=$(git rev-parse --short HEAD)"
echo "file_count=$(find . -type f -not -path './.git/*' | wc -l)"
for f in scripts/modeling/water_level_joint_encoder_decoder_v2.py \
         scripts/modeling/tidal_fluvial_hidden_gauge_v1_training.py \
         scripts/analysis/tidal_fluvial_hidden_gauge_v1_contract.py \
         results/modeling/wusongkou_astronomical_tide_v1_validation/tide_model.json \
         data/processed/water_level_model_input_v7_beijing_realtime_verified/realtime_features/datong_realtime_features.csv; do
    test -f "$f" && echo "present: $f" || echo "MISSING: $f"
done

echo "=== B. DIGEST CHAIN ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final || { echo "CONDA_ACTIVATE_FAILED"; exit 1; }
PYTHONPATH="$ROOT/pysite" python - "$ROOT/repo" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
reg = json.loads((root/"docs/records/ZHENJIANG_OYV_LEAVE_ONE_YEAR_OUT_DIRECTION_VALIDATION_V1_REGISTRY.json").read_bytes().decode("utf-8"))
def d(p): return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "absent"
base = root/"data/processed/water_level_model_input_v7_beijing_realtime_verified"
inp = [r for r,e in reg["input_identities"].items() if d(base/r)!=e["sha256"]]
src = [r for r,e in reg["source_identities"].items() if d(root/r)!=e["sha256"]]
tide = d(root/"results/modeling/wusongkou_astronomical_tide_v1_validation/tide_model.json")
print(json.dumps({"input_files": len(reg["input_identities"]), "input_mismatched": len(inp), "input_bad": inp,
                  "source_files": len(reg["source_identities"]), "source_mismatched": len(src), "source_bad": src,
                  "tide_model_matches_frozen": tide=="ce8512f28e87ab6d62814b064d91ca358b98efd7ee27b4f831322ea93775516d"},
                 indent=2, sort_keys=True))
PY

echo "=== C. SUBMIT THE LADDER AUDIT ==="
test -e "$ROOT/ladder_audit" && { echo "LADDER_AUDIT_ROOT_EXISTS, refusing"; exit 1; }
sed -i 's/\r$//' scripts/analysis/hpc/submit_independent_audit.slurm
AJ=$(sbatch --parsable \
    --export=ALL,AUDIT_FAMILY=ladder_v2,AUDIT_TASK_ROOT="$ROOT/ladder_tasks",AUDIT_EVAL_ROOT="$ROOT/ladder_impact",AUDIT_INFER_ROOT="$ROOT/ladder_impact",AUDIT_OUTPUT_SUBDIR=ladder_audit \
    scripts/analysis/hpc/submit_independent_audit.slurm 2>&1)
echo "ladder_audit_job=$AJ"
case "$AJ" in ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;; esac

echo "=== D. WAIT (max 75 min) ==="
for i in $(seq 1 450); do
    LEFT=$(squeue -j "$AJ" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 60)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== E. RESULT ==="
sacct -j "$AJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
cat "$ROOT/ladder_audit/independent_audit_summary.json" 2>/dev/null || echo "(no summary)"
echo "--- mismatch kinds ---"
tail -n +2 "$ROOT/ladder_audit/mismatches.csv" 2>/dev/null | cut -d, -f1 | sort | uniq -c | head || echo "(no rows)"
echo "--- stderr ---"
tail -14 "$ROOT/logs/independent_audit_${AJ}.err" 2>/dev/null || true
echo "=== END ==="
