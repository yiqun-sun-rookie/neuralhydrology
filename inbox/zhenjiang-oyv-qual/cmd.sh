#!/usr/bin/env bash
# zhenjiang out-of-year validation :: HPC environment qualification, step 2
# Clone the private code bundle, install two missing packages into a PRIVATE
# directory (nh_final is never modified), verify imports, then submit the
# synthetic-only qualification array job and collect its reports.
#
# Touches nothing outside /data1/home/sunyiq/zhenjiang_oyv_qual_20260819.
# Never reads station observations. Never touches the frozen R2 root,
# ~/neuralhydrology, or any other channel.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_qual_20260819
REPO_URL=git@github.com:yiqun-sun-rookie/zhenjiang-oyv-hpc.git

echo "=== A. GUARDS ==="
if [ -e "$ROOT" ]; then
    echo "QUAL_ROOT_ALREADY_EXISTS=$ROOT"
    echo "ABORT: refusing to reuse or overwrite an existing root"
    exit 1
fi
test -d /data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819 && \
    echo "frozen_r2_root_present=true (untouched by this command)" || \
    echo "frozen_r2_root_present=false"
mkdir -p "$ROOT/logs" "$ROOT/reports" "$ROOT/pysite" || exit 1
echo "root_created=$ROOT"

echo "=== B. CLONE PRIVATE CODE BUNDLE ==="
timeout 180 git clone --depth 1 "$REPO_URL" "$ROOT/repo" 2>&1 | tail -5
test -d "$ROOT/repo/qualification" || { echo "CLONE_FAILED"; exit 1; }
cd "$ROOT/repo" || exit 1
echo "bundle_commit=$(git rev-parse HEAD)"
echo "--- bundle file identities ---"
find . -type f -not -path './.git/*' | sort | while read -r f; do
    printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "${f#./}"
done

echo "=== C. ENVIRONMENT ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final || { echo "CONDA_ACTIVATE_FAILED"; exit 1; }
echo "python=$(command -v python)"

echo "=== D. PRIVATE DEPENDENCY INSTALL (nh_final NOT modified) ==="
echo "--- D1. threadpoolctl + joblib (pure python, required) ---"
timeout 600 python -m pip install --no-input --no-deps --target "$ROOT/pysite" \
    threadpoolctl joblib 2>&1 | tail -6
echo "d1_exit=$?"
# scikit-learn is only needed to satisfy an import used for version recording.
# CentOS 7 carries glibc 2.17, so recent manylinux_2_28 wheels may not apply.
# Fail fast on binary-only rather than starting a doomed source build; a failure
# here is reportable, not fatal.
echo "--- D2. scikit-learn (binary wheels only, optional) ---"
timeout 900 python -m pip install --no-input --no-deps --only-binary=:all: \
    --target "$ROOT/pysite" scikit-learn 2>&1 | tail -8
echo "d2_exit=$?"

echo "=== E. IMPORT VERIFICATION ==="
PYTHONPATH="$ROOT/pysite" python - <<'PY'
import importlib
import json
out = {}
for name in ("numpy", "pandas", "scipy", "sklearn", "psutil", "threadpoolctl", "joblib", "torch"):
    try:
        m = importlib.import_module(name)
        out[name] = str(getattr(m, "__version__", "unknown"))
    except Exception as exc:
        out[name] = "MISSING:%s:%s" % (type(exc).__name__, exc)
print(json.dumps(out, indent=2, sort_keys=True))
PY

echo "=== F. MODEL IMPORT ON LOGIN NODE (import only, no compute) ==="
PYTHONPATH="$ROOT/pysite" python - <<'PY'
import sys
from pathlib import Path
root = Path("/data1/home/sunyiq/zhenjiang_oyv_qual_20260819/repo")
for rel in ("scripts/modeling", "scripts/astronomical_tide", "scripts/analysis"):
    sys.path.insert(0, str(root / rel))
try:
    from water_level_joint_encoder_decoder_v2 import (
        RiverOrderTransformerEncoderDecoder,
        trainable_parameter_count,
    )
    model = RiverOrderTransformerEncoderDecoder()
    print("model_import_ok=True parameters=%d" % trainable_parameter_count(model))
except Exception as exc:
    print("model_import_ok=False %s: %s" % (type(exc).__name__, exc))
PY

echo "=== G. LINE ENDING FIX AND SUBMIT ==="
sed -i 's/\r$//' "$ROOT/repo/qualification/submit_qualification.slurm"
JID=$(sbatch --parsable "$ROOT/repo/qualification/submit_qualification.slurm" 2>&1)
echo "array_job_id=$JID"
case "$JID" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac

echo "=== H. WAIT (max 20 min) ==="
for i in $(seq 1 120); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 6)) -eq 0 ] && echo "t=$((i * 10))s remaining_tasks=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== I. SACCT ==="
sacct -j "$JID" -X --format=JobID%16,NodeList%10,State%12,ExitCode%8,Elapsed%10 2>&1 | head -20 || true

echo "=== J. PER-TASK NODE AND GPU ==="
grep -h -E 'task=|NVIDIA' "$ROOT"/logs/qual_${JID}_*.out 2>/dev/null | head -40 || true
echo "--- any fatal lines ---"
grep -h -E 'FATAL|Traceback|Error' "$ROOT"/logs/qual_${JID}_*.err 2>/dev/null | head -20 || true

echo "=== K. REPORT DIGEST ==="
PYTHONPATH="$ROOT/pysite" python - "$ROOT/reports" <<'PY'
import json
from pathlib import Path
import sys

rows = []
for path in sorted(Path(sys.argv[1]).glob("qual_*.json")):
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        rows.append({"file": path.name, "error": str(exc)})
        continue
    identity = payload.get("runtime_identity", {})
    first = payload.get("training_first") or {}
    rows.append({
        "file": path.name,
        "node": identity.get("node_name"),
        "gpu": identity.get("graphics_processor_name"),
        "gpu_capability": identity.get("graphics_processor_capability"),
        "gpu_uuid": identity.get("graphics_processor_unique_identifier"),
        "driver": identity.get("graphics_processor_driver_version"),
        "passed": payload.get("qualification_passed"),
        "numpy_direction_ok": payload.get("numpy_direction_check", {}).get("direction_rule_matches_local"),
        "numpy_differing": payload.get("numpy_direction_check", {}).get("differing_fields"),
        "intra_process_determinism": payload.get("intra_process_determinism"),
        "determinism_error": payload.get("deterministic_algorithms_error"),
        "state_sha256": first.get("state_sha256"),
        "prediction_sha256": first.get("prediction_sha256"),
        "elapsed_seconds": first.get("elapsed_seconds"),
        "sample_passes_per_second": first.get("sample_passes_per_second"),
    })

groups = {}
for row in rows:
    if row.get("state_sha256"):
        groups.setdefault((row.get("gpu"), row["state_sha256"]), []).append(row.get("node"))

print(json.dumps({
    "report_count": len(rows),
    "rows": rows,
    "state_hash_groups": [
        {"gpu": gpu, "state_sha256": digest, "nodes": nodes}
        for (gpu, digest), nodes in sorted(groups.items(), key=lambda item: str(item[0]))
    ],
}, indent=2, sort_keys=True, ensure_ascii=False))
PY

echo "=== L. ROOT FOOTPRINT ==="
du -sh "$ROOT" 2>/dev/null || true
echo "=== END ==="
