#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
FALLBACK_JOB_ID=216541
CANONICAL=src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm
EVIDENCE="$ROOT/results/31_hydrologic_dynamic_tokens/_submissions/gpu_probe_hgpu2_20260831_seq27"
DERIVED="$EVIDENCE/submit_gpu_resource_probe_hgpu2_30m.slurm"
EXPECTED_CANONICAL_SHA256=2a2df8a54a3c38e5b356024c91188d5db5d64e14b96e899efb4a42928bf2607f
EXPECTED_REGULARIZATION_SHA256=e8eb71123f99eecccd0316901ace54bd933f8e3565325696c1e0e11ea2b3b027
EXPECTED_CONFIG_SHA256=1f38ed828fb002a0b967c341d0109ff95ead50a7ad241925c5259343a1521b4e

test -d "$ROOT/.git"
test ! -e "$EVIDENCE"
mkdir -p "$EVIDENCE"
cd "$ROOT"

FALLBACK_LINE=$(squeue -j "$FALLBACK_JOB_ID" -h -o '%i|%j|%P|%T|%l')
printf '%s\n' "$FALLBACK_LINE" | tee "$EVIDENCE/fallback_before_submission.txt"
IFS='|' read -r ACTUAL_ID ACTUAL_NAME ACTUAL_PARTITION ACTUAL_STATE ACTUAL_LIMIT <<< "$FALLBACK_LINE"
test "$ACTUAL_ID" = "$FALLBACK_JOB_ID"
test "$ACTUAL_NAME" = "id31_gpu_probe"
test "$ACTUAL_PARTITION" = "hgpu2p"
test "$ACTUAL_STATE" = "PENDING"

test "$(sha256sum "$CANONICAL" | awk '{print $1}')" = "$EXPECTED_CANONICAL_SHA256"
test "$(sha256sum neuralhydrology/training/regularization.py | awk '{print $1}')" = \
  "$EXPECTED_REGULARIZATION_SHA256"
test "$(sha256sum src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml | awk '{print $1}')" = \
  "$EXPECTED_CONFIG_SHA256"

python - "$CANONICAL" "$DERIVED" "$EVIDENCE/derived_diff.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
diff_path = Path(sys.argv[3])
source = source_path.read_text(encoding="utf-8")
if source.count("#SBATCH --partition=hgpu2p") != 1:
    raise ValueError("Canonical partition line is not unique")
if source.count("#SBATCH --time=12:00:00") != 1:
    raise ValueError("Canonical time-limit line is not unique")
derived = source.replace("#SBATCH --partition=hgpu2p", "#SBATCH --partition=hgpu2", 1)
derived = derived.replace("#SBATCH --time=12:00:00", "#SBATCH --time=00:30:00", 1)
source_lines = source.splitlines()
derived_lines = derived.splitlines()
changes = [
    {"line": index, "canonical": before, "derived": after}
    for index, (before, after) in enumerate(zip(source_lines, derived_lines), start=1)
    if before != after
]
expected = [
    {
        "line": 3,
        "canonical": "#SBATCH --partition=hgpu2p",
        "derived": "#SBATCH --partition=hgpu2",
    },
    {
        "line": 9,
        "canonical": "#SBATCH --time=12:00:00",
        "derived": "#SBATCH --time=00:30:00",
    },
]
if changes != expected or len(source_lines) != len(derived_lines):
    raise ValueError(f"Unexpected derived-script changes: {changes!r}")
with target_path.open("x", encoding="utf-8", newline="\n") as stream:
    stream.write(derived)
report = {
    "canonical_path": source_path.as_posix(),
    "canonical_sha256": hashlib.sha256(source.encode()).hexdigest(),
    "derived_path": target_path.as_posix(),
    "derived_sha256": hashlib.sha256(derived.encode()).hexdigest(),
    "changes": changes,
}
with diff_path.open("x", encoding="utf-8") as stream:
    json.dump(report, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(report, indent=2, sort_keys=True))
PY

bash -n "$DERIVED"
DERIVED_SHA256=$(sha256sum "$DERIVED" | awk '{print $1}')
printf '%s  %s\n' "$DERIVED_SHA256" "$DERIVED" > "$EVIDENCE/derived.sha256"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY' | tee "$EVIDENCE/source_integrity_before_submission.json"
import json
from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

print(json.dumps(capture_source_integrity("DL01"), indent=2, sort_keys=True))
PY

SBATCH_OUTPUT=$(sbatch --parsable "$DERIVED")
ALTERNATIVE_JOB_ID=${SBATCH_OUTPUT%%;*}
case "$ALTERNATIVE_JOB_ID" in
  *[!0-9]*|'') echo "Unexpected sbatch output: $SBATCH_OUTPUT" >&2; exit 1 ;;
esac
printf '%s\n' "$ALTERNATIVE_JOB_ID" > "$EVIDENCE/alternative_job_id.txt"
squeue -j "$ALTERNATIVE_JOB_ID" -o '%.18i %.24j %.12P %.2t %.10l %.19S %.30R' \
  | tee "$EVIDENCE/squeue_after_submission.txt"
squeue --start -j "$ALTERNATIVE_JOB_ID" -o '%.18i %.24j %.12P %.10l %.19S %.30R' \
  | tee "$EVIDENCE/estimated_start.txt"

python - "$EVIDENCE" "$ALTERNATIVE_JOB_ID" "$FALLBACK_JOB_ID" "$DERIVED_SHA256" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

evidence = Path(sys.argv[1])
manifest = {
    "schema_version": 1,
    "status": "SUBMITTED",
    "scope": "same RTX 3090 resource probe on alternate hgpu2 partition",
    "alternative_probe_job_id": sys.argv[2],
    "alternative_probe_id": f"slurm{sys.argv[2]}",
    "fallback_probe_job_id": sys.argv[3],
    "derived_script_sha256": sys.argv[4],
    "allowed_scheduler_only_changes": ["partition hgpu2p to hgpu2", "time limit 12h to 30m"],
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
    "formal_evaluation_accessed": False,
}
with (evidence / "submission.json").open("x", encoding="utf-8") as stream:
    json.dump(manifest, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(manifest, indent=2, sort_keys=True))
PY

echo "ID31_ALTERNATIVE_GPU_PROBE_SUBMITTED $ALTERNATIVE_JOB_ID FALLBACK $FALLBACK_JOB_ID"
