#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
EVIDENCE="$ROOT/results/31_hydrologic_dynamic_tokens/_submissions/gpu_probe_retry_20260831_seq22"
PROBE_SCRIPT=src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm
EXPECTED_PROBE_SCRIPT_SHA256=2a2df8a54a3c38e5b356024c91188d5db5d64e14b96e899efb4a42928bf2607f
EXPECTED_REGULARIZATION_SHA256=e8eb71123f99eecccd0316901ace54bd933f8e3565325696c1e0e11ea2b3b027
EXPECTED_TEST_SHA256=45e497b85dad61f70b882a1ec3359b03d1cba2fed624934d1c03d61a467cb435
EXPECTED_CONFIG_SHA256=1f38ed828fb002a0b967c341d0109ff95ead50a7ad241925c5259343a1521b4e
EXPECTED_REGISTRY_SHA256=a7c99e9788f3d6f134f8087d1723c885d77f23e82ab59cba5a57d909e1460867

test -d "$ROOT/.git"
test ! -e "$EVIDENCE"
mkdir -p "$EVIDENCE"
cd "$ROOT"

test "$(sha256sum "$PROBE_SCRIPT" | awk '{print $1}')" = "$EXPECTED_PROBE_SCRIPT_SHA256"
test "$(sha256sum neuralhydrology/training/regularization.py | awk '{print $1}')" = \
  "$EXPECTED_REGULARIZATION_SHA256"
test "$(sha256sum test/test_hydrologic_dynamic_token_transformer.py | awk '{print $1}')" = \
  "$EXPECTED_TEST_SHA256"
test "$(sha256sum src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml | awk '{print $1}')" = \
  "$EXPECTED_CONFIG_SHA256"
test "$(sha256sum src/hydrologic_dynamic_tokens/registry/experiments.csv | awk '{print $1}')" = \
  "$EXPECTED_REGISTRY_SHA256"
bash -n "$PROBE_SCRIPT"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -m src.hydrologic_dynamic_tokens.scripts.audit_configs \
  2>&1 | tee "$EVIDENCE/config_audit.log"
python - <<'PY' | tee "$EVIDENCE/source_integrity_before_submission.json"
import json
from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

print(json.dumps(capture_source_integrity("DL01"), indent=2, sort_keys=True))
PY

squeue -u sunyiq -h -n id31_gpu_probe -o '%i|%j|%T|%R' | tee "$EVIDENCE/existing_probe_jobs.txt"
if test -s "$EVIDENCE/existing_probe_jobs.txt"; then
  echo "An ID31 GPU resource probe is already queued or running" >&2
  exit 1
fi

SBATCH_OUTPUT=$(sbatch --parsable "$PROBE_SCRIPT")
PROBE_JOB_ID=${SBATCH_OUTPUT%%;*}
case "$PROBE_JOB_ID" in
  *[!0-9]*|'') echo "Unexpected sbatch output: $SBATCH_OUTPUT" >&2; exit 1 ;;
esac
printf '%s\n' "$PROBE_JOB_ID" > "$EVIDENCE/probe_job_id.txt"
squeue -j "$PROBE_JOB_ID" -o '%.18i %.24j %.2t %.10M %.30R' | tee "$EVIDENCE/squeue_after_submission.txt"

python - "$EVIDENCE" "$PROBE_JOB_ID" "$EXPECTED_PROBE_SCRIPT_SHA256" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

evidence = Path(sys.argv[1])
manifest = {
    "schema_version": 1,
    "status": "SUBMITTED",
    "scope": "new GPU resource probe after evaluation-scalar fix; no validation or sealed evaluation",
    "probe_job_id": sys.argv[2],
    "probe_id": f"slurm{sys.argv[2]}",
    "probe_script": "src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm",
    "probe_script_sha256": sys.argv[3],
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
    "formal_evaluation_accessed": False,
}
with (evidence / "submission.json").open("x", encoding="utf-8") as stream:
    json.dump(manifest, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(manifest, indent=2, sort_keys=True))
PY

echo "ID31_GPU_RESOURCE_PROBE_SUBMITTED $PROBE_JOB_ID"
