#!/usr/bin/env bash
# Read-only export and issue-position audit for the four-target paper preflight.
set -euo pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
TASK_ERRORS="$ROOT/ladder_impact/ladder_task_errors.csv"
IMPACT_MANIFEST="$ROOT/ladder_impact/completion_manifest.json"
V1_AUDIT="$ROOT/independent_audit_r3"
LADDER_AUDIT="$ROOT/ladder_audit"
RELATIVE_FILES=(
  ladder_impact/ladder_task_errors.csv
  ladder_impact/completion_manifest.json
  independent_audit_r3/mismatches.csv
  independent_audit_r3/independent_audit_summary.json
  independent_audit_r3/completion_manifest.json
  ladder_audit/mismatches.csv
  ladder_audit/independent_audit_summary.json
  ladder_audit/completion_manifest.json
)

for relative in "${RELATIVE_FILES[@]}"; do
  test -f "$ROOT/$relative" || { echo "MISSING_FILE: $ROOT/$relative"; exit 1; }
done

printf '%s  %s\n' \
  '56416472db32cd10f0f95fd67e188765fc9eaa50ce774eb62e9812522ae2e576' "$TASK_ERRORS" \
  'd509e3185da72cb5fc58bbfd3b712db6493f65249dcf20a19307a11218e6edf2' "$IMPACT_MANIFEST" |
  sha256sum -c -
test "$(wc -l < "$TASK_ERRORS")" -eq 34561
grep -Fq '56416472db32cd10f0f95fd67e188765fc9eaa50ce774eb62e9812522ae2e576' "$IMPACT_MANIFEST"

for specification in "$V1_AUDIT:480" "$LADDER_AUDIT:960"; do
  audit_root="${specification%:*}"
  expected_count="${specification##*:}"
  grep -Fq '"audit_status": "reproducible"' "$audit_root/independent_audit_summary.json"
  grep -Fq '"mismatch_count": 0' "$audit_root/independent_audit_summary.json"
  grep -Fq "\"task_count_audited\": $expected_count" "$audit_root/independent_audit_summary.json"
  grep -Fq "\"prediction_package_count\": $expected_count" "$audit_root/independent_audit_summary.json"
  grep -Fq "\"reinference_count\": $expected_count" "$audit_root/independent_audit_summary.json"
  test "$(wc -l < "$audit_root/mismatches.csv")" -eq 1
  test "$(cat "$audit_root/mismatches.csv")" = 'kind,subject,expected,observed'
  grep -Fq '"status": "completed"' "$audit_root/completion_manifest.json"
done

echo '=== SOURCE_IDENTITIES ==='
for relative in "${RELATIVE_FILES[@]}"; do
  path="$ROOT/$relative"
  stat -c '%s bytes  %n' "$path"
  sha256sum "$path"
done

emit_bundle() {
  tar --format=gnu -C "$ROOT" -cf - "${RELATIVE_FILES[@]}" | gzip -1 -n
}

echo '=== EVIDENCE_BUNDLE_SHA256 ==='
emit_bundle | sha256sum
echo '=== EVIDENCE_BASE64_BEGIN ==='
emit_bundle | base64 -w 76
echo '=== EVIDENCE_BASE64_END ==='

python - "$ROOT" <<'PY'
import base64
import csv
import hashlib
import io
import json
import sys
import textwrap
from pathlib import Path

import numpy as np


root = Path(sys.argv[1])
years = tuple(range(2017, 2025))
seeds = (17, 29, 43, 57, 71, 83, 97, 109, 127, 139)
neighbours = {
    "zhenjiang": ("nanjing", "jiangyin"),
    "jiangyin": ("zhenjiang", "xuliujing"),
}
conditions = (
    "hidden_target",
    "hidden_target_upstream",
    "hidden_target_downstream",
    "hidden_target_both_nearest",
)
columns = (
    "source_task_id",
    "source_family",
    "test_year",
    "target",
    "source_condition",
    "seed",
    "issue_count",
    "first_issue_position",
    "last_issue_position",
    "ordered_issue_positions_sha256",
    "completion_manifest_byte_count",
    "completion_manifest_sha256",
    "prediction_artifact_byte_count",
    "prediction_artifact_sha256",
)


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


output = io.StringIO(newline="")
writer = csv.DictWriter(output, fieldnames=columns, lineterminator="\n")
writer.writeheader()
row_count = 0
for year in years:
    for target, (upstream, downstream) in neighbours.items():
        for canonical_condition in conditions:
            if canonical_condition in {
                "hidden_target",
                "hidden_target_both_nearest",
            }:
                source_family = "oyv_v1"
                source_condition = canonical_condition
                prefix = "zhenjiang_oyv_v1"
                task_root = root / "tasks"
            else:
                source_family = "ladder_v2"
                removed = (
                    upstream
                    if canonical_condition == "hidden_target_upstream"
                    else downstream
                )
                source_condition = "hidden_target_minus_" + removed
                prefix = "zhenjiang_ladder_v2"
                task_root = root / "ladder_tasks"
            for seed in seeds:
                task_id = (
                    f"{prefix}__fold_{year}__{target}__"
                    f"{source_condition}__seed_{seed}"
                )
                task_directory = task_root / task_id
                manifest_path = task_directory / "completion_manifest.json"
                prediction_path = task_directory / "test_predictions.npz"
                if not manifest_path.is_file() or not prediction_path.is_file():
                    raise RuntimeError(f"missing task artifact: {task_id}")
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                if manifest.get("task_id") != task_id or manifest.get("status") != "completed":
                    raise RuntimeError(f"invalid completion manifest: {task_id}")
                prediction_entries = [
                    entry
                    for entry in manifest.get("artifacts", [])
                    if entry.get("relative_path") == "test_predictions.npz"
                ]
                if len(prediction_entries) != 1:
                    raise RuntimeError(f"prediction manifest entry missing: {task_id}")
                prediction_entry = prediction_entries[0]
                if prediction_path.stat().st_size != prediction_entry["byte_count"]:
                    raise RuntimeError(f"prediction byte count changed: {task_id}")
                with np.load(prediction_path, allow_pickle=False) as package:
                    positions = package["issue_positions"]
                if (
                    positions.dtype != np.int64
                    or positions.ndim != 1
                    or positions.size == 0
                    or np.any(np.diff(positions) <= 0)
                ):
                    raise RuntimeError(f"invalid issue positions: {task_id}")
                little_endian = np.asarray(positions, dtype="<i8")
                writer.writerow(
                    {
                        "source_task_id": task_id,
                        "source_family": source_family,
                        "test_year": year,
                        "target": target,
                        "source_condition": source_condition,
                        "seed": seed,
                        "issue_count": positions.size,
                        "first_issue_position": positions[0],
                        "last_issue_position": positions[-1],
                        "ordered_issue_positions_sha256": hashlib.sha256(
                            little_endian.tobytes(order="C")
                        ).hexdigest(),
                        "completion_manifest_byte_count": manifest_path.stat().st_size,
                        "completion_manifest_sha256": sha256_file(manifest_path),
                        "prediction_artifact_byte_count": prediction_entry["byte_count"],
                        "prediction_artifact_sha256": prediction_entry["sha256"],
                    }
                )
                row_count += 1

if row_count != 640:
    raise RuntimeError(f"position audit row count {row_count} != 640")
payload = output.getvalue().encode("utf-8")
print("=== TASK_POSITION_AUDIT_IDENTITY ===")
print(f"byte_count={len(payload)}")
print(f"sha256={hashlib.sha256(payload).hexdigest()}")
print("row_count=640")
print("=== TASK_POSITION_AUDIT_BASE64_BEGIN ===")
print("\n".join(textwrap.wrap(base64.b64encode(payload).decode("ascii"), 76)))
print("=== TASK_POSITION_AUDIT_BASE64_END ===")
PY

echo '=== READ_ONLY_EXPORT_COMPLETE ==='
