#!/usr/bin/env bash
#SBATCH -J a64-hbv64-io
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH -t 01:00:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err

set -eo pipefail

ROOT=/data1/home/sunyiq/autoresearch64
PYTHON="$ROOT/.venv/bin/python"
RUNS="$ROOT/runs/unified_autoresearch"
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/payload/a64_gate_repair_seq46.tar.gz
PAYLOAD_SHA256=6bedefb2538f979a5896d236a09eabd58e5823fe9575ef1bec85bbe84f43add9
ATTEMPT="$RUNS/hbv_lite_64_hpc_reproduction_20260810_seq48"
SNAPSHOT="$ATTEMPT/snapshot"
EVIDENCE="$ATTEMPT/evidence"
CANDIDATE_RUN="$ATTEMPT/candidate_run"
SOURCE64="$RUNS/development_source_real_64_hpc"
PACKAGE64="$RUNS/development_packages_real_64_hpc"
ELIGIBILITY="$RUNS/BASIN_ELIGIBILITY_64_HPC.json"
SELECTION="$SNAPSHOT/src/unified_autoresearch/selection/development_basins_64_v1.json"
PROTOCOL="$SNAPSHOT/src/unified_autoresearch/protocols/development_v1.json"

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

echo "=== VERIFY AND EXTRACT IMMUTABLE TEST SNAPSHOT ==="
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
(cd "$SNAPSHOT" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$EVIDENCE/SNAPSHOT_MANIFEST.sha256"
(cd "$SNAPSHOT" && sha256sum -c "$EVIDENCE/SNAPSHOT_MANIFEST.sha256" >/dev/null)

echo "=== INITIALIZE IMMUTABLE SNAPSHOT AS A GIT REPOSITORY ==="
(
  cd "$SNAPSHOT"
  git init -q
  git config user.name "Unified Autoresearch Snapshot"
  git config user.email "snapshot@localhost"
  git add -- .
  GIT_AUTHOR_DATE='2026-08-10T00:00:00+00:00' GIT_COMMITTER_DATE='2026-08-10T00:00:00+00:00' \
    git commit -q -m "Immutable sequence 48 test snapshot"
  git rev-parse HEAD > "$EVIDENCE/SNAPSHOT_GIT_COMMIT.txt"
  test -z "$(git status --porcelain --untracked-files=all)"
)
echo "payload_sha256=$ACTUAL_PAYLOAD_SHA256"
echo "snapshot_manifest_entries=$(wc -l < "$EVIDENCE/SNAPSHOT_MANIFEST.sha256")"
echo "snapshot_manifest_check=ok"

run_pytest_gate() {
  LABEL=$1
  shift
  XML="$EVIDENCE/${LABEL}.xml"
  STDOUT="$EVIDENCE/${LABEL}_STDOUT.txt"
  JSON="$EVIDENCE/${LABEL}.json"
  set +e
  cd "$SNAPSHOT"
  PYTHONPATH="$SNAPSHOT/src" "$PYTHON" -m pytest "$@" -q -p no:cacheprovider \
    --junitxml="$XML" 2>&1 | tee "$STDOUT"
  TEST_RC=${PIPESTATUS[0]}
  set -e
  "$PYTHON" - "$XML" "$TEST_RC" "$JSON" "$LABEL" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

xml_path = Path(sys.argv[1])
process_exit_code = int(sys.argv[2])
output_path = Path(sys.argv[3])
label = sys.argv[4]
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
    "label": label,
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
}

echo "=== TARGETED LINUX REGRESSION GATE ==="
run_pytest_gate TARGETED_GATE \
  src/unified_autoresearch/tests/test_restricted_runtime.py::test_candidate_cannot_redirect_path_checks_by_replacing_os_path_helpers \
  src/unified_autoresearch/tests/test_restricted_runtime.py::test_candidate_cannot_replace_the_os_path_module_used_by_the_audit_hook \
  src/unified_autoresearch/tests/test_frozen_dependency_sets.py \
  src/unified_autoresearch/tests/test_single_candidate_development.py \
  src/unified_autoresearch/tests/test_reference_candidates.py::test_each_reference_candidate_trains_and_predicts_through_registered_runtime \
  src/unified_autoresearch/tests/test_development_recovery.py::test_registered_recovery_matches_a_clean_deterministic_training_run \
  src/unified_autoresearch/tests/test_development_recovery.py::test_full_development_loop_produces_exactly_32_finite_registered_cells \
  src/unified_autoresearch/tests/test_development_recovery.py::test_full_development_loop_supervises_every_registered_run_when_declared

echo "=== COMPLETE LINUX SAFETY TEST GATE ==="
run_pytest_gate FULL_GATE src/unified_autoresearch/tests

echo "=== FROZEN 64-BASIN PACKAGE GATE ==="
"$PYTHON" - "$SOURCE64" "$PACKAGE64" "$ELIGIBILITY" "$SELECTION" "$PROTOCOL" "$EVIDENCE/PACKAGE_GATE.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

source_root = Path(sys.argv[1])
package_root = Path(sys.argv[2])
eligibility_path = Path(sys.argv[3])
selection_path = Path(sys.argv[4])
protocol_path = Path(sys.argv[5])
output_path = Path(sys.argv[6])

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
eligibility = json.loads(eligibility_path.read_text(encoding="utf-8"))
selection = json.loads(selection_path.read_text(encoding="utf-8"))
protocol = json.loads(protocol_path.read_text(encoding="utf-8"))

assert source["schema_version"] == "development_source_v1"
assert source["source_kind"] == "explicitly_pre_sliced_development_only"
assert source["date_bounds"] == ["1999-10-01", "2008-09-30"]
assert source["sealed_final_evaluation_present"] is False
for relative, expected in source["files"].items():
    assert sha256(source_root / relative) == expected, relative

expected_basins = [str(value).zfill(8) for value in selection["basins"]]
assert len(expected_basins) == 64 and len(set(expected_basins)) == 64
assert package["schema_version"] == "development_packages_v1"
assert package["basins"] == expected_basins
assert package["protocols"] == ["forward", "reverse"]
assert package["development_protocols"] == protocol["development_protocols"]
assert package["source_manifest_sha256"] == sha256(source_manifest_path)
assert package["source_files"] == source["files"]
for relative, expected in package["files"].items():
    assert sha256(package_root / relative) == expected, relative
for windows in package["development_protocols"].values():
    for start, end in windows.values():
        assert "1999-10-01" <= start <= end <= "2008-09-30"

package_manifest_sha256 = sha256(package_manifest_path)
assert eligibility["package_manifest_sha256"] == package_manifest_sha256
assert eligibility["protocols"] == ["forward", "reverse"]
assert len(eligibility["standard_basins"]) == 53
assert len(eligibility["unstable_basins"]) == 11
assert set(eligibility["standard_basins"]) | set(eligibility["unstable_basins"]) == set(expected_basins)
assert not (set(eligibility["standard_basins"]) & set(eligibility["unstable_basins"]))

summary = {
    "schema_version": "frozen_64_basin_package_gate_v1",
    "basin_count": len(expected_basins),
    "protocols": package["protocols"],
    "date_bounds": source["date_bounds"],
    "sealed_final_evaluation_present": source["sealed_final_evaluation_present"],
    "source_manifest_sha256": sha256(source_manifest_path),
    "package_manifest_sha256": package_manifest_sha256,
    "package_file_count": len(package["files"]),
    "standard_basin_count": len(eligibility["standard_basins"]),
    "unstable_basin_count": len(eligibility["unstable_basins"]),
}
with output_path.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(summary, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(summary, sort_keys=True))
PY

echo "=== RUN ONE PREDECLARED HBV-LITE CANDIDATE ON 64 DEVELOPMENT BASINS ==="
cd "$ROOT"
PYTHONPATH="$SNAPSHOT/src" "$PYTHON" -u "$SNAPSHOT/src/unified_autoresearch/scripts/run_single_candidate.py" \
  --candidate hbv_lite \
  --dependencies cluster \
  --repo-root "$ROOT" \
  --package-root "$PACKAGE64" \
  --output-root "$CANDIDATE_RUN" \
  --monitor-sample-interval-seconds 1.0 \
  --monitor-reason "restricted 64-basin development reproduction after complete Linux gate; one predeclared candidate" \
  | tee "$EVIDENCE/CANDIDATE_COMMAND_STDOUT.txt"

echo "=== INDEPENDENT REPRODUCTION EVIDENCE CHECK ==="
"$PYTHON" - "$ATTEMPT" "$SNAPSHOT" "$PACKAGE64" "$ELIGIBILITY" "$PAYLOAD_SHA256" <<'PY'
import hashlib
import importlib.metadata
import json
import os
import socket
import statistics
import sys
from pathlib import Path

attempt = Path(sys.argv[1])
snapshot = Path(sys.argv[2])
package_root = Path(sys.argv[3])
eligibility_path = Path(sys.argv[4])
payload_sha256 = sys.argv[5]
candidate_root = attempt / "candidate_run"
evidence = attempt / "evidence"

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

candidate_summary_path = candidate_root / "CANDIDATE_SUMMARY.json"
candidate = json.loads(candidate_summary_path.read_text(encoding="utf-8"))
targeted_gate = json.loads((evidence / "TARGETED_GATE.json").read_text(encoding="utf-8"))
full_gate = json.loads((evidence / "FULL_GATE.json").read_text(encoding="utf-8"))
package_gate = json.loads((evidence / "PACKAGE_GATE.json").read_text(encoding="utf-8"))
eligibility = json.loads(eligibility_path.read_text(encoding="utf-8"))

assert targeted_gate["candidate_launch_allowed"] is True
assert full_gate["candidate_launch_allowed"] is True
assert candidate["candidate_id"] == "hbv-lite-calibrated-v1"
assert candidate["basin_count"] == 64
assert candidate["cell_count"] == 64
assert candidate["registered_run_count"] == 4
assert candidate["score_report_count"] == 2
assert candidate["sealed_final_evaluation_read_or_scored"] is False
assert candidate["fair_benchmark_scoring_program_run"] is False
assert candidate["formal_basin_search_run"] is False
assert candidate["baseline_outperformance_claimed"] is False
assert candidate["package_manifest_sha256"] == package_gate["package_manifest_sha256"]

runtime_paths = sorted(candidate_root.rglob("runtime-result.json"))
assert len(runtime_paths) == 4
runtimes = []
for path in runtime_paths:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert value["status"] == "succeeded"
    assert value["process_exit_code"] == 0
    assert value["normalized_exit_code"] == 0
    assert value["denied_event_count"] == 0
    assert value["required_outputs_complete"] is True
    runtimes.append({"path": path.relative_to(attempt).as_posix(), **value})

access_paths = sorted(candidate_root.rglob("access.jsonl"))
assert len(access_paths) == 4
independent_denials = 0
access_event_count = 0
for path in access_paths:
    events = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
    access_event_count += len(events)
    independent_denials += sum(event.get("decision") == "deny" for event in events)
assert independent_denials == 0

cells = candidate["cells"]
by_basin = {str(cell["basin"]).zfill(8): cell for cell in cells}
assert len(by_basin) == 64
assert set(by_basin) == set(eligibility["standard_basins"]) | set(eligibility["unstable_basins"])

def metrics(basins):
    values = [float(by_basin[basin]["mean_nse"]) for basin in basins]
    return {
        "count": len(values),
        "median_mean_nse": statistics.median(values),
        "minimum_mean_nse": min(values),
        "maximum_mean_nse": max(values),
        "positive_mean_nse_count": sum(value > 0.0 for value in values),
    }

all_basins = [str(cell["basin"]).zfill(8) for cell in cells]
group_metrics = {
    "all": metrics(all_basins),
    "standard": metrics(eligibility["standard_basins"]),
    "unstable": metrics(eligibility["unstable_basins"]),
}
reference_metrics = {
    "all": {"median_mean_nse": 0.5022568476184368, "minimum_mean_nse": -8.627963014524003, "maximum_mean_nse": 0.8864327627041511, "positive_mean_nse_count": 54},
    "standard": {"median_mean_nse": 0.5456194110972769, "minimum_mean_nse": -8.627963014524003, "maximum_mean_nse": 0.8864327627041511, "positive_mean_nse_count": 46},
    "unstable": {"median_mean_nse": 0.32027179570466113, "minimum_mean_nse": -4.968356050952189, "maximum_mean_nse": 0.5425052462668687, "positive_mean_nse_count": 8},
}
metric_deltas = {
    group: {key: group_metrics[group][key] - value for key, value in expected.items()}
    for group, expected in reference_metrics.items()
}
canonical_cells = json.dumps(cells, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
canonical_cells_sha256 = hashlib.sha256(canonical_cells).hexdigest()

source_files = (
    "src/unified_autoresearch/candidates/catalog.py",
    "src/unified_autoresearch/candidates/implementations/hbv_lite.py",
    "src/unified_autoresearch/data/packages.py",
    "src/unified_autoresearch/runtime/bootstrap.py",
    "src/unified_autoresearch/runtime/dependencies.py",
    "src/unified_autoresearch/runtime/runner.py",
    "src/unified_autoresearch/scripts/run_single_candidate.py",
    "src/unified_autoresearch/selection/development_basins_64_v1.json",
    "src/unified_autoresearch/workflow/candidate_development.py",
)
summary = {
    "schema_version": "hbv_lite_64_hpc_reproduction_v1",
    "experiment_id": "hbv_lite_64_hpc_reproduction_20260810_seq48",
    "job_id": os.environ.get("SLURM_JOB_ID"),
    "host": socket.gethostname(),
    "payload_sha256": payload_sha256,
    "snapshot_git_commit": (evidence / "SNAPSHOT_GIT_COMMIT.txt").read_text(encoding="utf-8").strip(),
    "snapshot_manifest_entry_count": len((evidence / "SNAPSHOT_MANIFEST.sha256").read_text(encoding="utf-8").splitlines()),
    "candidate_id": candidate["candidate_id"],
    "targeted_test_gate": targeted_gate,
    "full_test_gate": full_gate,
    "package_gate": package_gate,
    "basin_count": candidate["basin_count"],
    "cell_count": candidate["cell_count"],
    "registered_run_count": candidate["registered_run_count"],
    "score_report_count": candidate["score_report_count"],
    "runtime_count": len(runtimes),
    "runtimes": runtimes,
    "access_log_count": len(access_paths),
    "access_event_count": access_event_count,
    "independently_counted_denials": independent_denials,
    "group_metrics": group_metrics,
    "windows_reference_metrics": reference_metrics,
    "metric_deltas_from_windows_reference": metric_deltas,
    "canonical_cells_sha256": canonical_cells_sha256,
    "windows_reference_canonical_cells_sha256": "cb40ab9547817e8a728d3a6196ade2e7fa68d609db497970e93d818a7a22e023",
    "windows_reference_cells_exact_match": canonical_cells_sha256 == "cb40ab9547817e8a728d3a6196ade2e7fa68d609db497970e93d818a7a22e023",
    "candidate_summary_sha256": sha256(candidate_summary_path),
    "package_manifest_sha256": sha256(package_root / "PACKAGE_MANIFEST.json"),
    "runtime_source_sha256": {relative: sha256(snapshot / relative) for relative in source_files},
    "dependency_versions": {name: importlib.metadata.version(name) for name in ("numpy", "pandas", "pyarrow")},
    "sealed_final_evaluation_read_or_scored": False,
    "fair_benchmark_scoring_program_run": False,
    "formal_basin_search_run": False,
    "baseline_outperformance_claimed": False,
}
path = evidence / "REPRODUCTION_SUMMARY.json"
with path.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(summary, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps({
    "experiment_id": summary["experiment_id"],
    "job_id": summary["job_id"],
    "candidate_id": summary["candidate_id"],
    "targeted_test_gate": summary["targeted_test_gate"],
    "full_test_gate": summary["full_test_gate"],
    "basin_count": summary["basin_count"],
    "runtime_count": summary["runtime_count"],
    "independently_counted_denials": summary["independently_counted_denials"],
    "group_metrics": summary["group_metrics"],
    "windows_reference_cells_exact_match": summary["windows_reference_cells_exact_match"],
}, sort_keys=True))
PY

echo "=== FINALIZE COMPLETE ATTEMPT MANIFEST ==="
echo "summary=$EVIDENCE/REPRODUCTION_SUMMARY.json"
echo "manifest=$EVIDENCE/MANIFEST.sha256"
echo "candidate_summary=$CANDIDATE_RUN/CANDIDATE_SUMMARY.json"
exec 1>&- 2>&-
cd "$ATTEMPT"
find . -type f ! -path './evidence/MANIFEST.sha256' -print0 | sort -z | xargs -0 sha256sum > evidence/MANIFEST.sha256
sha256sum -c evidence/MANIFEST.sha256 >/dev/null
