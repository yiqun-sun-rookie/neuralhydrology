#!/usr/bin/env bash
# zhenjiang out-of-year validation :: step 7
# Update the deployment clone to the verbatim-transport commit, verify the whole
# digest chain on the cluster side, then run the static audit AS A BATCH JOB.
# The previous round ran that audit on the login node, which is computation and
# is forbidden there; this corrects it. Nothing heavy runs in this script.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. UPDATE CLONE ==="
cd "$ROOT/repo" || { echo "REPO_MISSING"; exit 1; }
timeout 600 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -3
timeout 120 git reset -q --hard refs/remotes/origin/main
echo "bundle_commit=$(git rev-parse HEAD)"
echo "file_count=$(find . -type f -not -path './.git/*' | wc -l)"

echo "=== B. FULL DIGEST CHAIN ON THE CLUSTER ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final || { echo "CONDA_ACTIVATE_FAILED"; exit 1; }
PYTHONPATH="$ROOT/pysite" python - "$ROOT/repo" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
reg = json.loads((root / "docs/records/ZHENJIANG_OYV_LEAVE_ONE_YEAR_OUT_DIRECTION_VALIDATION_V1_REGISTRY.json").read_bytes().decode("utf-8"))
prereg_path = root / "docs/records/ZHENJIANG_OYV_LEAVE_ONE_YEAR_OUT_DIRECTION_VALIDATION_V1_PREREGISTRATION.json"
prereg = json.loads(prereg_path.read_bytes().decode("utf-8"))

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "absent"

src_bad = [r for r, e in reg["source_identities"].items() if digest(root / r) != e["sha256"]]
base = root / "data/processed/water_level_model_input_v7_beijing_realtime_verified"
in_bad = [r for r, e in reg["input_identities"].items() if digest(base / r) != e["sha256"]]
bound_bad = [a["relative_path"] for a in prereg["2_bound_upstream_artifacts"]["artifacts"] if digest(root / a["relative_path"]) != a["sha256"]]
print(json.dumps({
    "bundle_commit_in_registry": reg["deployment_bundle"]["commit"],
    "source_files": len(reg["source_identities"]), "source_mismatched": len(src_bad), "source_bad": src_bad,
    "input_files": len(reg["input_identities"]), "input_mismatched": len(in_bad), "input_bad": in_bad,
    "bound_artifacts": len(prereg["2_bound_upstream_artifacts"]["artifacts"]), "bound_mismatched": len(bound_bad), "bound_bad": bound_bad,
    "preregistration_matches_registry": digest(prereg_path) == reg["preregistration"]["sha256"],
    "task_count": reg["task_count"],
}, indent=2, sort_keys=True))
PY

echo "=== C. SUBMIT STATIC AUDIT AS A BATCH JOB ==="
JID=$(sbatch --parsable scripts/analysis/hpc/submit_static_audit.slurm 2>&1)
echo "static_audit_job=$JID"
case "$JID" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac

echo "=== D. WAIT (max 30 min) ==="
for i in $(seq 1 180); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 12)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== E. AUDIT RESULT ==="
sacct -j "$JID" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
grep -E '"gate"|"finding_count"|"blocking_finding_count"|"tests_run"|"kind"|"subject"' \
    "$ROOT"/logs/static_audit_${JID}.out 2>/dev/null | head -30 || true
echo "--- stderr tail ---"
tail -12 "$ROOT"/logs/static_audit_${JID}.err 2>/dev/null || true
echo "=== END ==="
