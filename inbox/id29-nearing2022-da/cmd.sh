#!/bin/bash
# ID29 seq=235: verify and recover the ngu104-excluded >=18-coordinate audit when terminal.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB_ID=202729
JOB_NAME=N22-part-audit7
TARGET=N22-EVAL-TS-DA-L04-TE050-S0
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq234_v1"
PREVIOUS="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq223_v1"
STDOUT="$ROOT/closure_20260810/logs/${JOB_NAME}_${JOB_ID}.out"
STDERR="$ROOT/closure_20260810/logs/${JOB_NAME}_${JOB_ID}.err"

echo "=== JOB RECORD ==="
RECORD=$(sacct -n -X -P -j "$JOB_ID" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList,Reason | head -n 1)
printf '%s\n' "$RECORD"
STATE=$(printf '%s\n' "$RECORD" | awk -F'|' '{print $3}')
EXIT_CODE=$(printf '%s\n' "$RECORD" | awk -F'|' '{print $4}')
NODE=$(printf '%s\n' "$RECORD" | awk -F'|' '{print $8}')

case "$STATE" in
  PENDING|RUNNING|CONFIGURING|COMPLETING)
    echo "audit_terminal=false"
    exit 0
    ;;
esac

echo "=== OUTPUT PATHS ==="
for path in "$STDOUT" "$STDERR"; do
  if test -f "$path"; then
    stat -c '%n|%s|%y' "$path"
    sha256sum "$path"
  else
    echo "missing=$path"
  fi
done

if test "$STATE" != "COMPLETED" || test "$EXIT_CODE" != "0:0"; then
  echo "=== STDOUT ==="
  test -f "$STDOUT" && cat "$STDOUT"
  echo "=== STDERR ==="
  test -f "$STDERR" && cat "$STDERR"
  echo "=== FINAL AND STAGING INVENTORY ==="
  if test -e "$FINAL"; then
    find "$FINAL" -maxdepth 3 -printf '%p|%y|%s\n' | sort
  else
    echo "final_exists=false"
  fi
  for staging in "$(dirname "$FINAL")"/partial_numerical_audit_seq234_v1.preparing-*; do
    if test -d "$staging"; then
      find "$staging" -maxdepth 2 -type f -printf '%p|%s\n' -exec sha256sum {} \;
      if test -f "$staging/role_snapshot.json"; then
        echo "=== ROLE SNAPSHOT ==="
        cat "$staging/role_snapshot.json"
      fi
    fi
  done
  echo "audit_terminal_failure=$STATE/$EXIT_CODE" >&2
  exit 1
fi

test "$NODE" != "ngu104"
test -d "$FINAL"
test -d "$PREVIOUS"
test -f "$STDOUT"
test -f "$STDERR"
test ! -s "$STDERR"
test "$(find "$FINAL" -type l -print -quit)" = ""
cmp "$FINAL/audit_1.json" "$FINAL/audit_2.json"
cmp "$FINAL/audit_stdout_1.json" "$FINAL/audit_stdout_2.json"
sha256sum "$STDOUT" "$STDERR" "$FINAL"/*

python - "$FINAL" "$PREVIOUS" "$JOB_ID" "$NODE" "$TARGET" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

final = Path(sys.argv[1])
previous = Path(sys.argv[2])
job_id = sys.argv[3]
node = sys.argv[4]
target = sys.argv[5]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


audit_bytes = (final / "audit_1.json").read_bytes()
audit = json.loads(audit_bytes)
audit_2 = json.loads((final / "audit_2.json").read_bytes())
old = json.loads((previous / "audit_1.json").read_bytes())
role_path = final / "role_snapshot.json"
role = json.loads(role_path.read_text(encoding="utf-8"))
receipt_path = final / "execution_receipt.json"
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
manifest_path = final / "artifact_manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

if audit != audit_2:
    raise ValueError("Repeated audits are not object-identical")
if audit["complete_coordinates"] < 18:
    raise ValueError("Terminal audit contains fewer than 18 complete coordinates")
if audit["comparison_rows"] != audit["complete_coordinates"] * 7:
    raise ValueError("Terminal audit does not contain seven metrics per coordinate")
if audit["registered_matrix_modified"] or audit["frozen_acceptance_modified"]:
    raise ValueError("Frozen input modification reported")

if node == "ngu104" or role["slurm_node"] == "ngu104":
    raise ValueError("Excluded node ngu104 executed the retry")
if role["slurm_job_id"] != job_id or receipt["slurm_job_id"] != job_id:
    raise ValueError("Job identifier differs across scheduler, snapshot, or receipt")
if role["slurm_node"] != node or receipt["slurm_node"] != node:
    raise ValueError("Node differs across scheduler, snapshot, or receipt")
if role["partial_complete_count"] != audit["complete_coordinates"]:
    raise ValueError("Role snapshot and numerical audit count differ")
if role["partial_complete_count"] != role["closure_complete_count"]:
    raise ValueError("Complete-role algorithms disagree")
if role["partial_minus_closure"] or role["closure_minus_partial"]:
    raise ValueError("Complete-role algorithms report different coordinates")
if not role["target_partial_complete"] or not role["target_closure_complete"]:
    raise ValueError("Target is not complete under both role algorithms")
if set(role["target_roles"]) != {
    "candidate_config", "candidate_checkpoint", "candidate_log",
    "candidate_prediction", "candidate_metrics", "reference_prediction",
    "reference_metrics",
}:
    raise ValueError("Target role set differs from the seven-role contract")
for name, item in role["target_roles"].items():
    if not item["exists"] or not item["is_file"] or item["is_dir"] or item["is_symlink"]:
        raise ValueError(f"Target role is not a regular file: {name}={item}")

old_coordinates = {row["eval_id"]: row for row in old["coordinates"]}
new_coordinates = {row["eval_id"]: row for row in audit["coordinates"]}
if not set(old_coordinates) < set(new_coordinates):
    raise ValueError("The new audit does not strictly extend the predecessor")
if any(old_coordinates[key] != new_coordinates[key] for key in old_coordinates):
    raise ValueError("A predecessor coordinate object changed")
added = sorted(set(new_coordinates) - set(old_coordinates))
if target not in added:
    raise ValueError(f"Expected newly complete target is absent: {added}")

old_sources = old["source_artifacts"]
new_sources = audit["source_artifacts"]
if any(old_sources[key] != new_sources.get(key) for key in old_sources):
    raise ValueError("A predecessor source-artifact record changed")
added_sources = sorted(set(new_sources) - set(old_sources))

files = []
for path in sorted(final.rglob("*")):
    if path.is_symlink():
        raise ValueError(f"Link in final audit: {path}")
    if path.is_file() and path.name != "artifact_manifest.json":
        files.append({
            "path": path.relative_to(final).as_posix(),
            "bytes": path.stat().st_size,
            "sha256": digest(path),
        })
if manifest["files"] != files:
    raise ValueError("Artifact manifest does not match live final files")
if manifest["file_count"] != len(files):
    raise ValueError("Artifact manifest file count differs")
if manifest["total_bytes"] != sum(row["bytes"] for row in files):
    raise ValueError("Artifact manifest byte count differs")
if receipt["mailbox_sequence"] != 234:
    raise ValueError("Execution receipt has the wrong mailbox sequence")
if receipt["complete_coordinates"] != audit["complete_coordinates"]:
    raise ValueError("Execution receipt coordinate count differs")
if receipt["comparison_rows"] != audit["comparison_rows"]:
    raise ValueError("Execution receipt comparison count differs")
if receipt["compute_node_role_snapshot_sha256"] != digest(role_path):
    raise ValueError("Execution receipt role-snapshot hash differs")
if receipt["audit_sha256"] != digest(final / "audit_1.json"):
    raise ValueError("Execution receipt audit hash differs")

summary = {
    "schema": "nearing2022-partial-numerical-audit-seq234-terminal-verification-v1",
    "job_id": job_id,
    "slurm_node": node,
    "excluded_node_respected": node != "ngu104",
    "complete_coordinates": audit["complete_coordinates"],
    "complete_by_family": audit["complete_by_family"],
    "comparison_rows": audit["comparison_rows"],
    "individual_tolerance_failures": audit["individual_tolerance_failures"],
    "coordinates_with_failures": audit["coordinates_with_failures"],
    "added_coordinates": added,
    "added_coordinate_decisions": {
        key: {
            "failed_metrics": new_coordinates[key]["failed_metrics"],
            "all_seven_metrics_within_tolerance": not new_coordinates[key]["failed_metrics"],
        }
        for key in added
    },
    "target_roles_regular_files": 7,
    "predecessor_coordinates_identical": len(old_coordinates),
    "predecessor_source_records_identical": len(old_sources),
    "source_artifacts": len(new_sources),
    "source_artifact_bytes": sum(row["bytes"] for row in new_sources.values()),
    "unique_source_hashes": len({row["sha256"] for row in new_sources.values()}),
    "added_source_artifacts": added_sources,
    "audit_bytes": len(audit_bytes),
    "audit_sha256": hashlib.sha256(audit_bytes).hexdigest(),
    "role_snapshot_bytes": role_path.stat().st_size,
    "role_snapshot_sha256": digest(role_path),
    "artifact_manifest_bytes": manifest_path.stat().st_size,
    "artifact_manifest_sha256": digest(manifest_path),
    "execution_receipt_bytes": receipt_path.stat().st_size,
    "execution_receipt_sha256": digest(receipt_path),
    "repeated_audits_byte_identical": (final / "audit_1.json").read_bytes() == (final / "audit_2.json").read_bytes(),
    "repeated_summaries_byte_identical": (final / "audit_stdout_1.json").read_bytes() == (final / "audit_stdout_2.json").read_bytes(),
    "registered_matrix_modified": False,
    "frozen_acceptance_modified": False,
}
print(json.dumps(summary, indent=2, sort_keys=True))
PY

echo "=== AUDIT BASE64 BEGIN ==="
base64 -w 0 "$FINAL/audit_1.json"
echo
echo "=== AUDIT BASE64 END ==="
echo "=== ROLE SNAPSHOT BASE64 BEGIN ==="
base64 -w 0 "$FINAL/role_snapshot.json"
echo
echo "=== ROLE SNAPSHOT BASE64 END ==="
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
echo "audit_terminal=true"
