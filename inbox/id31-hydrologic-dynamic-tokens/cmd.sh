#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
PROBE_JOB_ID=216548
FALLBACK_JOB_ID=216541
PROBE_REPORT="$ROOT/results/31_hydrologic_dynamic_tokens/_gpu_resource_probes/slurm${PROBE_JOB_ID}/probe_report.json"
EXPECTED_PROBE_REPORT_SHA256=079e940fa74c4b3917bb6310881c14dee91c6c88f8700f29d59c1e0518841dce
CANONICAL=src/hydrologic_dynamic_tokens/hpc/submit_development_experiment.slurm
EXPECTED_CANONICAL_SHA256=99e6b130fb2d10c0d229aa0befc3f820c5dfce4cbf431261c2d93a9a51258baa
EVIDENCE="$ROOT/results/31_hydrologic_dynamic_tokens/_submissions/slurm216548_hgpu2_DL01_seq30"
DERIVED="$EVIDENCE/submit_DL01_slurm216548_hgpu2.slurm"

test -d "$ROOT/.git"
test -f "$PROBE_REPORT"
test ! -e "$EVIDENCE"
mkdir -p "$EVIDENCE"
cd "$ROOT"

test "$(sha256sum "$PROBE_REPORT" | awk '{print $1}')" = "$EXPECTED_PROBE_REPORT_SHA256"
test "$(sha256sum "$CANONICAL" | awk '{print $1}')" = "$EXPECTED_CANONICAL_SHA256"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

python - "$PROBE_REPORT" <<'PY' | tee "$EVIDENCE/probe_binding_audit.json"
import json
import sys
from pathlib import Path

from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

path = Path(sys.argv[1])
report = json.loads(path.read_text(encoding="utf-8"))
expected_checks = {
    "actual_full_batch_and_context_observed",
    "candidate_safe_access_passed",
    "cuda_available",
    "device_is_rtx_3090",
    "gradient_is_nonzero",
    "gradients_are_finite",
    "one_model_forward_call",
    "one_update_loss_finite",
    "optimizer_state_exists",
    "optimizer_step_is_exactly_one",
    "peak_allocated_below_20_gib",
    "safe_bundle_unchanged",
    "source_integrity_unchanged",
}
current_source = capture_source_integrity("DL01")
assert report["status"] == "PASS", report["status"]
assert set(report["checks"]) == expected_checks, set(report["checks"])
assert all(report["checks"].values()), report["checks"]
assert report["probe_id"] == "slurm216548", report["probe_id"]
assert report["experiment_id"] == "DL01", report["experiment_id"]
assert report["device_name"] == "NVIDIA GeForce RTX 3090", report["device_name"]
assert report["source_integrity_before"] == current_source
assert report["source_integrity_after"] == current_source
assert report["formal_evaluation_accessed"] is False
summary = {
    "status": "PASS",
    "probe_id": report["probe_id"],
    "device_name": report["device_name"],
    "check_count": len(report["checks"]),
    "all_checks_passed": all(report["checks"].values()),
    "source_before_equals_after_equals_current": True,
    "formal_evaluation_accessed": False,
}
print(json.dumps(summary, indent=2, sort_keys=True))
PY

PROBE_SACCT=$(sacct -j "$PROBE_JOB_ID" -X -n -P --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList \
  | awk -F'|' -v id="$PROBE_JOB_ID" '$1 == id {print; exit}')
printf '%s\n' "$PROBE_SACCT" | tee "$EVIDENCE/probe_sacct.txt"
IFS='|' read -r PROBE_ACTUAL_ID PROBE_NAME PROBE_PARTITION PROBE_STATE PROBE_EXIT PROBE_ELAPSED PROBE_NODE <<< "$PROBE_SACCT"
test "$PROBE_ACTUAL_ID" = "$PROBE_JOB_ID"
test "$PROBE_NAME" = "id31_gpu_probe"
test "$PROBE_PARTITION" = "hgpu2"
test "$PROBE_STATE" = "COMPLETED"
test "$PROBE_EXIT" = "0:0"

FALLBACK_LINE=$(squeue -j "$FALLBACK_JOB_ID" -h -o '%i|%j|%P|%T|%l')
printf '%s\n' "$FALLBACK_LINE" | tee "$EVIDENCE/fallback_before_cancel.txt"
IFS='|' read -r FALLBACK_ACTUAL_ID FALLBACK_NAME FALLBACK_PARTITION FALLBACK_STATE FALLBACK_LIMIT <<< "$FALLBACK_LINE"
test "$FALLBACK_ACTUAL_ID" = "$FALLBACK_JOB_ID"
test "$FALLBACK_NAME" = "id31_gpu_probe"
test "$FALLBACK_PARTITION" = "hgpu2p"
test "$FALLBACK_STATE" = "PENDING"
scancel "$FALLBACK_JOB_ID"
for _ in $(seq 1 10); do
  if ! squeue -j "$FALLBACK_JOB_ID" -h | grep -q .; then break; fi
  sleep 1
done
test -z "$(squeue -j "$FALLBACK_JOB_ID" -h -o '%i')"
sacct -j "$FALLBACK_JOB_ID" -X -n -P --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList \
  | tee "$EVIDENCE/fallback_after_cancel.txt"

python - "$CANONICAL" "$DERIVED" "$EVIDENCE/derived_diff.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
diff_path = Path(sys.argv[3])
source = source_path.read_text(encoding="utf-8")
replacements = [
    ("#SBATCH --partition=hgpu2p", "#SBATCH --partition=hgpu2"),
    ('PROBE_JOB_ID="__PROBE_JOB_ID__"', 'PROBE_JOB_ID="216548"'),
    ('EXPERIMENT_ID="__EXPERIMENT_ID__"', 'EXPERIMENT_ID="DL01"'),
]
derived = source
for before, after in replacements:
    if derived.count(before) != 1:
        raise ValueError(f"Expected one canonical occurrence: {before!r}")
    derived = derived.replace(before, after, 1)
source_lines = source.splitlines()
derived_lines = derived.splitlines()
changes = [
    {"line": index, "canonical": before, "derived": after}
    for index, (before, after) in enumerate(zip(source_lines, derived_lines), start=1)
    if before != after
]
expected = [
    {"line": 3, "canonical": "#SBATCH --partition=hgpu2p", "derived": "#SBATCH --partition=hgpu2"},
    {
        "line": 16,
        "canonical": 'PROBE_JOB_ID="__PROBE_JOB_ID__"',
        "derived": 'PROBE_JOB_ID="216548"',
    },
    {
        "line": 17,
        "canonical": 'EXPERIMENT_ID="__EXPERIMENT_ID__"',
        "derived": 'EXPERIMENT_ID="DL01"',
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
test "$(sha256sum "$CANONICAL" | awk '{print $1}')" = "$EXPECTED_CANONICAL_SHA256"
python -m src.hydrologic_dynamic_tokens.scripts.audit_configs \
  2>&1 | tee "$EVIDENCE/config_audit.log"

if squeue -u sunyiq -h -o '%j' | grep -Fxq 'id31_development'; then
  echo "A concurrent ID31 development job is already present" >&2
  exit 1
fi

SBATCH_OUTPUT=$(sbatch --parsable "$DERIVED")
DEVELOPMENT_JOB_ID=${SBATCH_OUTPUT%%;*}
case "$DEVELOPMENT_JOB_ID" in
  *[!0-9]*|'') echo "Unexpected sbatch output: $SBATCH_OUTPUT" >&2; exit 1 ;;
esac
printf '%s\n' "$DEVELOPMENT_JOB_ID" > "$EVIDENCE/development_job_id.txt"
squeue -j "$DEVELOPMENT_JOB_ID" -o '%.18i %.24j %.12P %.2t %.10M %.10l %.30R' \
  | tee "$EVIDENCE/squeue_after_submission.txt"
squeue --start -j "$DEVELOPMENT_JOB_ID" -o '%.18i %.24j %.12P %.10l %.19S %.30R' \
  | tee "$EVIDENCE/estimated_start.txt"

python - "$EVIDENCE" "$DEVELOPMENT_JOB_ID" "$DERIVED_SHA256" "$EXPECTED_PROBE_REPORT_SHA256" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

evidence = Path(sys.argv[1])
manifest = {
    "schema_version": 1,
    "status": "SUBMITTED",
    "experiment_id": "DL01",
    "development_job_id": sys.argv[2],
    "run_id": f"id31_DL01_s100_slurm{sys.argv[2]}",
    "seed": 100,
    "restart_mode": "full retraining from initialization; no state reused from failed job 215880",
    "bound_probe_job_id": "216548",
    "bound_probe_report_sha256": sys.argv[4],
    "derived_script_sha256": sys.argv[3],
    "partition": "hgpu2",
    "device_contract": "NVIDIA GeForce RTX 3090",
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
    "formal_evaluation_accessed": False,
}
with (evidence / "submission.json").open("x", encoding="utf-8") as stream:
    json.dump(manifest, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(manifest, indent=2, sort_keys=True))
PY

echo "ID31_DL01_RETRY_SUBMITTED $DEVELOPMENT_JOB_ID PROBE $PROBE_JOB_ID"
