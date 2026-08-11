#!/bin/bash
# ID29 seq=206: verify and recover the isolated >=15-coordinate numerical audit when terminal.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB_ID=202610
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq205_v1"
PREVIOUS="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq192_v1"
STDOUT="$ROOT/closure_20260810/logs/N22-part-audit3_${JOB_ID}.out"
STDERR="$ROOT/closure_20260810/logs/N22-part-audit3_${JOB_ID}.err"

echo "=== JOB RECORD ==="
RECORD=$(sacct -n -X -P -j "$JOB_ID" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList,Reason | head -n 1)
printf '%s\n' "$RECORD"
STATE=$(printf '%s\n' "$RECORD" | awk -F'|' '{print $3}')
EXIT_CODE=$(printf '%s\n' "$RECORD" | awk -F'|' '{print $4}')

case "$STATE" in
  COMPLETED)
    test "$EXIT_CODE" = "0:0"
    ;;
  PENDING|RUNNING|CONFIGURING|COMPLETING)
    echo "audit_terminal=false"
    exit 0
    ;;
  *)
    echo "audit_terminal_failure=$STATE/$EXIT_CODE" >&2
    exit 1
    ;;
esac

echo "=== TERMINAL ARTIFACT CHECK ==="
test -d "$FINAL"
test -d "$PREVIOUS"
test -f "$STDOUT"
test -f "$STDERR"
test ! -s "$STDERR"
test "$(find "$FINAL" -type l -print -quit)" = ""
cmp "$FINAL/audit_1.json" "$FINAL/audit_2.json"
cmp "$FINAL/audit_stdout_1.json" "$FINAL/audit_stdout_2.json"
sha256sum "$STDOUT" "$STDERR" "$FINAL"/*

python - "$FINAL" "$PREVIOUS" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

final = Path(sys.argv[1])
previous = Path(sys.argv[2])


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


audit_bytes = (final / "audit_1.json").read_bytes()
audit = json.loads(audit_bytes)
audit_2 = json.loads((final / "audit_2.json").read_bytes())
old = json.loads((previous / "audit_1.json").read_bytes())
receipt = json.loads((final / "execution_receipt.json").read_text(encoding="utf-8"))
manifest_path = final / "artifact_manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

if audit != audit_2:
    raise ValueError("Repeated audits are not object-identical")
if audit["complete_coordinates"] < 15:
    raise ValueError("Terminal audit contains fewer than 15 complete coordinates")
if audit["comparison_rows"] != audit["complete_coordinates"] * 7:
    raise ValueError("Terminal audit does not contain seven metrics per coordinate")
if audit["registered_matrix_modified"] or audit["frozen_acceptance_modified"]:
    raise ValueError("Frozen input modification reported")

old_coordinates = {row["eval_id"]: row for row in old["coordinates"]}
new_coordinates = {row["eval_id"]: row for row in audit["coordinates"]}
if not set(old_coordinates) < set(new_coordinates):
    raise ValueError("The new audit does not strictly extend the 14-coordinate predecessor")
if any(old_coordinates[key] != new_coordinates[key] for key in old_coordinates):
    raise ValueError("A predecessor coordinate object changed")
added = sorted(set(new_coordinates) - set(old_coordinates))
expected = "N22-EVAL-TS-DA-L02-TE100-S0"
if expected not in added:
    raise ValueError(f"Expected newly complete coordinate is absent: {added}")

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
if receipt["slurm_job_id"] != "202610":
    raise ValueError("Execution receipt has the wrong job identifier")
if receipt["mailbox_sequence"] != 205:
    raise ValueError("Execution receipt has the wrong mailbox sequence")
if receipt["complete_coordinates"] != audit["complete_coordinates"]:
    raise ValueError("Execution receipt coordinate count differs")
if receipt["comparison_rows"] != audit["comparison_rows"]:
    raise ValueError("Execution receipt comparison count differs")
if receipt["audit_sha256"] != digest(final / "audit_1.json"):
    raise ValueError("Execution receipt audit hash differs")

summary = {
    "schema": "nearing2022-partial-numerical-audit-seq205-terminal-verification-v1",
    "job_id": "202610",
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
    "predecessor_coordinates_identical": len(old_coordinates),
    "predecessor_source_records_identical": len(old_sources),
    "source_artifacts": len(new_sources),
    "source_artifact_bytes": sum(row["bytes"] for row in new_sources.values()),
    "unique_source_hashes": len({row["sha256"] for row in new_sources.values()}),
    "added_source_artifacts": added_sources,
    "audit_bytes": len(audit_bytes),
    "audit_sha256": hashlib.sha256(audit_bytes).hexdigest(),
    "artifact_manifest_bytes": manifest_path.stat().st_size,
    "artifact_manifest_sha256": digest(manifest_path),
    "execution_receipt_bytes": (final / "execution_receipt.json").stat().st_size,
    "execution_receipt_sha256": digest(final / "execution_receipt.json"),
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
echo "audit_terminal=true"
