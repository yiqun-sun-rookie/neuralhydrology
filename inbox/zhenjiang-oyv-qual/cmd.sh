#!/usr/bin/env bash
# zhenjiang out-of-year validation :: deploy and smoke, step 6
# Create the formal execution root, clone the full deployment bundle, install the
# three private dependencies, verify the input identities on the cluster side,
# then run ONE training task into a throwaway smoke directory.
# The smoke result is not evidence and never enters the formal task root.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
REPO_URL=git@github.com:yiqun-sun-rookie/zhenjiang-oyv-hpc.git

echo "=== A. GUARDS ==="
if [ -e "$ROOT" ]; then
    echo "EXECUTION_ROOT_ALREADY_EXISTS=$ROOT"
    echo "ABORT: refusing to reuse or overwrite an existing root"
    exit 1
fi
mkdir -p "$ROOT/logs" "$ROOT/pysite" || exit 1
echo "root_created=$ROOT"

echo "=== B. CLONE DEPLOYMENT BUNDLE ==="
timeout 600 git clone --depth 1 "$REPO_URL" "$ROOT/repo" 2>&1 | tail -4
test -d "$ROOT/repo/scripts/modeling" || { echo "CLONE_FAILED"; exit 1; }
cd "$ROOT/repo" || exit 1
echo "bundle_commit=$(git rev-parse HEAD)"
echo "file_count=$(find . -type f -not -path './.git/*' | wc -l)"
du -sh --exclude=.git . 2>/dev/null | head -1

echo "=== C. PRIVATE DEPENDENCIES ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final || { echo "CONDA_ACTIVATE_FAILED"; exit 1; }
timeout 900 python -m pip install --no-input --no-deps --only-binary=:all: \
    --target "$ROOT/pysite" scikit-learn threadpoolctl joblib 2>&1 | tail -5
ls -1 "$ROOT/pysite" | grep -E 'dist-info$' || true

echo "=== D. INPUT IDENTITY ON THE CLUSTER SIDE ==="
PYTHONPATH="$ROOT/pysite" python - "$ROOT/repo" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
prereg = json.loads((root / "docs/records/ZHENJIANG_OYV_LEAVE_ONE_YEAR_OUT_DIRECTION_VALIDATION_V1_PREREGISTRATION.json").read_text(encoding="utf-8"))
registered = {}
registered.update(prereg["3_input_data"]["feature_files_sha256"])
registered.update(prereg["3_input_data"]["target_files_sha256"])
base = root / "data/processed/water_level_model_input_v7_beijing_realtime_verified"
bad = []
for rel, want in sorted(registered.items()):
    got = hashlib.sha256((base / rel).read_bytes()).hexdigest()
    if got != want:
        bad.append({"file": rel, "expected": want, "observed": got})
tide = root / "results/modeling/wusongkou_astronomical_tide_v1_validation/tide_model.json"
tide_digest = hashlib.sha256(tide.read_bytes()).hexdigest()
print(json.dumps({
    "checked": len(registered),
    "mismatched": len(bad),
    "mismatches": bad,
    "tide_model_sha256": tide_digest,
    "tide_model_matches_frozen": tide_digest == "ce8512f28e87ab6d62814b064d91ca358b98efd7ee27b4f831322ea93775516d",
}, indent=2, sort_keys=True))
PY

echo "=== E. STATIC AUDIT ON THE CLUSTER ==="
PYTHONPATH="$ROOT/pysite" timeout 1800 python -u scripts/analysis/static_audit_zhenjiang_oyv_v1.py 2>&1 | tail -25

echo "=== F. SUBMIT ONE SMOKE TRAINING TASK ==="
sed -i 's/\r$//' scripts/modeling/hpc/submit_zhenjiang_oyv_v1.slurm
JID=$(sbatch --parsable --array=0-0 --export=ALL,OYV_OUTPUT_SUBDIR=smoke \
    scripts/modeling/hpc/submit_zhenjiang_oyv_v1.slurm 2>&1)
echo "smoke_job=$JID"
case "$JID" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac

echo "=== G. WAIT (max 25 min) ==="
for i in $(seq 1 150); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 6)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== H. RESULT ==="
sacct -j "$JID" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -5
tail -40 "$ROOT"/logs/train_${JID}_0.out 2>/dev/null || true
echo "--- stderr tail ---"
tail -20 "$ROOT"/logs/train_${JID}_0.err 2>/dev/null || true

echo "=== I. SMOKE ARTIFACTS ==="
find "$ROOT/smoke" -type f 2>/dev/null | head -10 || true
cat "$ROOT"/smoke/*/completion_manifest.json 2>/dev/null | head -40 || true
echo "=== END ==="
