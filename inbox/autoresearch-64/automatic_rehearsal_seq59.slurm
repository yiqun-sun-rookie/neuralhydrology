#!/usr/bin/env bash
#SBATCH -J a64-auto3x8-r1
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH -t 00:45:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err

set -eo pipefail

ROOT=/data1/home/sunyiq/autoresearch64
PYTHON="$ROOT/.venv/bin/python"
RUNS="$ROOT/runs/unified_autoresearch"
SOURCE_COMMIT=65b31c823e5368e202215cf1c4d9d52a286a547c
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/payload/automatic_rehearsal_source_crlf_65b31c82.tar.gz
PAYLOAD_SHA256=1f08efbebdf74b6ce2dbfda1c1fa00aaf9dfc95358dcb2e7eab9b5ff45dbe227
ATTEMPT="$RUNS/automatic_rehearsal_8x3_20260811_seq59"
SNAPSHOT="$ATTEMPT/snapshot"
EVIDENCE="$ATTEMPT/evidence"
REHEARSAL="$ATTEMPT/rehearsal"
SOURCE8="$RUNS/hbv_lite_8_hpc_smoke_20260810_seq36/source_8"
PACKAGE8="$RUNS/hbv_lite_8_hpc_smoke_20260810_seq36/packages_8"
SELECTION="$SNAPSHOT/src/unified_autoresearch/selection/development_basins_v1.json"
POLICY="$SNAPSHOT/src/unified_autoresearch/protocols/automatic_rehearsal_v1.json"

if [ -e "$ATTEMPT" ]; then
  echo "REFUSE_EXISTING_OUTPUT $ATTEMPT"
  exit 3
fi
mkdir -p "$SNAPSHOT" "$EVIDENCE"
exec > "$EVIDENCE/JOB_STDOUT.txt" 2> "$EVIDENCE/JOB_STDERR.txt"

export PYTHONDONTWRITEBYTECODE=1
export PYTHONNOUSERSITE=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

echo "=== VERIFY IMMUTABLE SOURCE SNAPSHOT ==="
ACTUAL_PAYLOAD_SHA256=$(sha256sum "$PAYLOAD" | awk '{print $1}')
if [ "$ACTUAL_PAYLOAD_SHA256" != "$PAYLOAD_SHA256" ]; then
  echo "PAYLOAD_HASH_MISMATCH expected=$PAYLOAD_SHA256 actual=$ACTUAL_PAYLOAD_SHA256"
  exit 4
fi
tar -xzf "$PAYLOAD" -C "$SNAPSHOT"
test "$(sha256sum "$SNAPSHOT/src/fair_benchmark/frozen/bundle/track0_statics.csv" | awk '{print $1}')" = \
  "085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2"
test "$(sha256sum "$SNAPSHOT/examples/06-Finetuning/531_basin_list.txt" | awk '{print $1}')" = \
  "cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85"
printf '%s\n' 'runs/' '.pytest_cache/' '__pycache__/' '*.py[cod]' > "$SNAPSHOT/.gitignore"
printf '%s\n' "$SOURCE_COMMIT" > "$EVIDENCE/SOURCE_COMMIT.txt"
(cd "$SNAPSHOT" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$EVIDENCE/SNAPSHOT_MANIFEST.sha256"
(cd "$SNAPSHOT" && sha256sum -c "$EVIDENCE/SNAPSHOT_MANIFEST.sha256" >/dev/null)

echo "=== INITIALIZE SNAPSHOT REPOSITORY ==="
(
  cd "$SNAPSHOT"
  git init -q
  git config user.name "Unified Autoresearch Snapshot"
  git config user.email "snapshot@localhost"
  git add -- .
  GIT_AUTHOR_DATE='2026-08-11T00:00:00+00:00' GIT_COMMITTER_DATE='2026-08-11T00:00:00+00:00' \
    git commit -q -m "Immutable three-candidate rehearsal snapshot"
  git rev-parse HEAD > "$EVIDENCE/SNAPSHOT_GIT_COMMIT.txt"
  test -z "$(git status --porcelain --untracked-files=all)"
)
echo "source_commit=$SOURCE_COMMIT"
echo "payload_sha256=$ACTUAL_PAYLOAD_SHA256"
echo "snapshot_manifest_entries=$(wc -l < "$EVIDENCE/SNAPSHOT_MANIFEST.sha256")"

echo "=== COMPLETE LINUX SAFETY TEST GATE ==="
set +e
cd "$SNAPSHOT"
PYTHONPATH="$SNAPSHOT/src" "$PYTHON" -m pytest src/unified_autoresearch/tests -q -p no:cacheprovider \
  --junitxml="$EVIDENCE/FULL_GATE.xml" 2>&1 | tee "$EVIDENCE/FULL_GATE_STDOUT.txt"
TEST_RC=${PIPESTATUS[0]}
set -e
"$PYTHON" - "$EVIDENCE/FULL_GATE.xml" "$TEST_RC" "$EVIDENCE/FULL_GATE.json" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

xml_path = Path(sys.argv[1])
process_exit_code = int(sys.argv[2])
output_path = Path(sys.argv[3])
root = ET.parse(xml_path).getroot()

def total(name: str) -> int:
    if name in root.attrib:
        return int(float(root.attrib[name]))
    return sum(int(float(node.attrib.get(name, 0))) for node in root.findall(".//testsuite"))

tests = total("tests")
failures = total("failures")
errors = total("errors")
skipped = total("skipped")
summary = {
    "schema_version": "unified_autoresearch_linux_test_gate_v1",
    "process_exit_code": process_exit_code,
    "tests": tests,
    "passed": tests - failures - errors - skipped,
    "failures": failures,
    "errors": errors,
    "skipped": skipped,
    "candidate_launch_allowed": process_exit_code == 0 and failures == 0 and errors == 0,
}
with output_path.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(summary, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(summary, sort_keys=True))
if not summary["candidate_launch_allowed"]:
    raise SystemExit(10)
PY

echo "=== FROZEN EIGHT-BASIN PACKAGE GATE ==="
"$PYTHON" - "$SOURCE8" "$PACKAGE8" "$SELECTION" "$EVIDENCE/PACKAGE_GATE.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

source_root = Path(sys.argv[1])
package_root = Path(sys.argv[2])
selection_path = Path(sys.argv[3])
output_path = Path(sys.argv[4])

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

source_manifest_path = source_root / "SOURCE_MANIFEST.json"
package_manifest_path = package_root / "PACKAGE_MANIFEST.json"
source = json.loads(source_manifest_path.read_text(encoding="utf-8"))
package = json.loads(package_manifest_path.read_text(encoding="utf-8"))
selection = json.loads(selection_path.read_text(encoding="utf-8"))
basins = [str(value).zfill(8) for value in selection["basins"]]

assert len(basins) == 8 and len(set(basins)) == 8
assert source["schema_version"] == "development_source_v1"
assert source["source_kind"] == "explicitly_pre_sliced_development_only"
assert source["date_bounds"] == ["1999-10-01", "2008-09-30"]
assert source["sealed_final_evaluation_present"] is False
for relative, expected in source["files"].items():
    assert sha256(source_root / relative) == expected, relative
assert package["schema_version"] == "development_packages_v1"
assert package["basins"] == basins
assert package["protocols"] == ["forward", "reverse"]
assert package["source_manifest_sha256"] == sha256(source_manifest_path)
for relative, expected in package["files"].items():
    assert sha256(package_root / relative) == expected, relative
for windows in package["development_protocols"].values():
    for start, end in windows.values():
        assert "1999-10-01" <= start <= end <= "2008-09-30"

summary = {
    "schema_version": "frozen_eight_basin_package_gate_v1",
    "basin_count": len(basins),
    "basins": basins,
    "date_bounds": source["date_bounds"],
    "sealed_final_evaluation_present": source["sealed_final_evaluation_present"],
    "source_manifest_sha256": sha256(source_manifest_path),
    "package_manifest_sha256": sha256(package_manifest_path),
    "package_file_count": len(package["files"]),
}
with output_path.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(summary, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(summary, sort_keys=True))
PY

echo "=== RUN THREE-CANDIDATE AUTOMATIC REHEARSAL ==="
cd "$ROOT"
PYTHONPATH="$SNAPSHOT/src" "$PYTHON" -u "$SNAPSHOT/src/unified_autoresearch/scripts/run_automatic_rehearsal.py" \
  --dependencies cluster \
  --repo-root "$ROOT" \
  --package-root "$PACKAGE8" \
  --policy-path "$POLICY" \
  --output-root "$REHEARSAL" \
  --monitor-sample-interval-seconds 1.0 \
  --monitor-reason "restricted eight-basin three-candidate automatic-research rehearsal" \
  | tee "$EVIDENCE/REHEARSAL_COMMAND_STDOUT.txt"

echo "=== INDEPENDENT RAW-EVIDENCE CHECK ==="
"$PYTHON" - "$ATTEMPT" "$PACKAGE8" "$SOURCE_COMMIT" "$PAYLOAD_SHA256" <<'PY'
import hashlib
import importlib.metadata
import json
import os
import socket
import statistics
import sys
from pathlib import Path

attempt = Path(sys.argv[1])
package_root = Path(sys.argv[2])
source_commit = sys.argv[3]
payload_sha256 = sys.argv[4]
rehearsal_root = attempt / "rehearsal"
evidence = attempt / "evidence"

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

loop_path = rehearsal_root / "REHEARSAL_SUMMARY.json"
proposal_path = rehearsal_root / "PROPOSAL_REGISTRY.json"
loop = json.loads(loop_path.read_text(encoding="utf-8"))
proposal = json.loads(proposal_path.read_text(encoding="utf-8"))
full_gate = json.loads((evidence / "FULL_GATE.json").read_text(encoding="utf-8"))
package_gate = json.loads((evidence / "PACKAGE_GATE.json").read_text(encoding="utf-8"))

assert full_gate["candidate_launch_allowed"] is True
assert package_gate["basin_count"] == 8
assert package_gate["sealed_final_evaluation_present"] is False
assert proposal["proposal_count"] == 3
assert proposal["result_dependent_proposal_inputs"] is False
assert proposal["sealed_final_evaluation_input"] is False
assert proposal["fair_benchmark_score_input"] is False
assert len({row["candidate_id"] for row in proposal["proposals"]}) == 3
assert len({row["category"] for row in proposal["proposals"]}) == 3
assert all(row["seed"] == 29 for row in proposal["proposals"])

assert loop["schema_version"] == "automatic_rehearsal_v1"
assert loop["candidate_count"] == 3
assert loop["basin_count"] == 8
assert loop["registered_run_count"] == 12
assert loop["score_report_count"] == 6
assert loop["protocol_basin_metric_count"] == 48
assert loop["cell_count"] == 24
assert loop["total_denied_event_count"] == 0
assert loop["sealed_final_evaluation_read_or_scored"] is False
assert loop["fair_benchmark_scoring_program_run"] is False
assert loop["formal_basin_search_run"] is False
assert loop["baseline_outperformance_claimed"] is False
assert sum(row["recommended_for_64_basin_validation"] for row in loop["ranking"]) == 1

runtime_paths = sorted(rehearsal_root.rglob("runtime-result.json"))
access_paths = sorted(rehearsal_root.rglob("access.jsonl"))
score_paths = sorted(rehearsal_root.glob("candidates/*/scores/*.json"))
candidate_summary_paths = sorted(rehearsal_root.glob("candidates/*/CANDIDATE_SUMMARY.json"))
assert len(runtime_paths) == 12
assert len(access_paths) == 12
assert len(score_paths) == 6
assert len(candidate_summary_paths) == 3

runtimes = []
for path in runtime_paths:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert value["status"] == "succeeded"
    assert value["process_exit_code"] == 0
    assert value["normalized_exit_code"] == 0
    assert value["denied_event_count"] == 0
    assert value["required_outputs_complete"] is True
    assert value["output_contract"]["valid"] is True
    assert value["output_contract"]["failures"] == []
    runtimes.append({"path": path.relative_to(attempt).as_posix(), **value})

access_event_count = 0
independent_denials = 0
for path in access_paths:
    events = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
    access_event_count += len(events)
    independent_denials += sum(event.get("decision") == "deny" for event in events)
assert independent_denials == 0

basins = package_gate["basins"]
raw_metrics = {}
candidate_ids = set()
for candidate_path in candidate_summary_paths:
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    candidate_id = candidate["candidate_id"]
    candidate_ids.add(candidate_id)
    protocol_metrics = {}
    for protocol in ("forward", "reverse"):
        score_path = candidate_path.parent / candidate["protocols"][protocol]["score_path"]
        score = json.loads(score_path.read_text(encoding="utf-8"))
        assert score["candidate_id"] == candidate_id
        assert set(score["basin_metrics"]) == set(basins)
        protocol_metrics[protocol] = score["basin_metrics"]
    mean_values = [
        (float(protocol_metrics["forward"][basin]) + float(protocol_metrics["reverse"][basin])) / 2.0
        for basin in basins
    ]
    raw_metrics[candidate_id] = statistics.median(mean_values)

assert candidate_ids == {row["candidate_id"] for row in proposal["proposals"]}
recomputed_ranking = sorted(raw_metrics, key=lambda candidate_id: (-raw_metrics[candidate_id], candidate_id))
reported_ranking = [row["candidate_id"] for row in sorted(loop["ranking"], key=lambda row: row["rank"])]
assert recomputed_ranking == reported_ranking
for row in loop["ranking"]:
    assert abs(float(row["median_mean_nse"]) - raw_metrics[row["candidate_id"]]) <= 1e-15
assert loop["recommended_candidate_id"] == recomputed_ranking[0]

summary = {
    "schema_version": "automatic_rehearsal_hpc_evidence_v1",
    "experiment_id": "automatic_rehearsal_8x3_20260811_seq59",
    "retry_of_job_id": "202551",
    "changed_factor": "snapshot packaging preserves the preregistered Windows bytes of the two frozen input files",
    "job_id": os.environ.get("SLURM_JOB_ID"),
    "host": socket.gethostname(),
    "source_commit": source_commit,
    "payload_sha256": payload_sha256,
    "snapshot_git_commit": (evidence / "SNAPSHOT_GIT_COMMIT.txt").read_text(encoding="utf-8").strip(),
    "full_test_gate": full_gate,
    "package_gate": package_gate,
    "proposal_count": proposal["proposal_count"],
    "proposals": proposal["proposals"],
    "candidate_count": loop["candidate_count"],
    "registered_run_count": loop["registered_run_count"],
    "runtime_count": len(runtimes),
    "runtimes": runtimes,
    "score_report_count": len(score_paths),
    "protocol_basin_metric_count": loop["protocol_basin_metric_count"],
    "cell_count": loop["cell_count"],
    "access_log_count": len(access_paths),
    "access_event_count": access_event_count,
    "independently_counted_denials": independent_denials,
    "independently_recomputed_median_mean_nse": raw_metrics,
    "independently_recomputed_ranking": recomputed_ranking,
    "reported_ranking": loop["ranking"],
    "recommended_candidate_id": loop["recommended_candidate_id"],
    "proposal_registry_sha256": sha256(proposal_path),
    "rehearsal_summary_sha256": sha256(loop_path),
    "package_manifest_sha256": sha256(package_root / "PACKAGE_MANIFEST.json"),
    "dependency_versions": {
        name: importlib.metadata.version(name) for name in ("numpy", "pandas", "pyarrow")
    },
    "sealed_final_evaluation_read_or_scored": False,
    "fair_benchmark_scoring_program_run": False,
    "formal_basin_search_run": False,
    "baseline_outperformance_claimed": False,
    "limitation": "This rehearsal verifies a constrained closed loop; it does not establish scientific novelty or baseline superiority.",
}
path = evidence / "REHEARSAL_EVIDENCE.json"
with path.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(summary, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps({
    "experiment_id": summary["experiment_id"],
    "job_id": summary["job_id"],
    "full_test_gate": summary["full_test_gate"],
    "candidate_count": summary["candidate_count"],
    "runtime_count": summary["runtime_count"],
    "score_report_count": summary["score_report_count"],
    "independently_counted_denials": summary["independently_counted_denials"],
    "independently_recomputed_median_mean_nse": summary["independently_recomputed_median_mean_nse"],
    "recommended_candidate_id": summary["recommended_candidate_id"],
}, sort_keys=True))
PY

echo "=== FINALIZE ATTEMPT MANIFEST ==="
echo "summary=$EVIDENCE/REHEARSAL_EVIDENCE.json"
echo "manifest=$EVIDENCE/MANIFEST.sha256"
echo "rehearsal_summary=$REHEARSAL/REHEARSAL_SUMMARY.json"
exec 1>&- 2>&-
cd "$ATTEMPT"
find . -type f ! -path './evidence/MANIFEST.sha256' -print0 | sort -z | xargs -0 sha256sum > evidence/MANIFEST.sha256
sha256sum -c evidence/MANIFEST.sha256 >/dev/null
