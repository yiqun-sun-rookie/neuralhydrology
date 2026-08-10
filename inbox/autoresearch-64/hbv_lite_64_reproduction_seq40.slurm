#!/usr/bin/env bash
#SBATCH -J a64-hbv64-repro
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
SNAPSHOT="$RUNS/dlopen_timezone_fix_validation_20260809_seq24"
SOURCE64="$RUNS/development_source_real_64_hpc"
PACKAGE64="$RUNS/development_packages_real_64_hpc"
ELIGIBILITY="$RUNS/BASIN_ELIGIBILITY_64_HPC.json"
ATTEMPT="$RUNS/hbv_lite_64_hpc_reproduction_20260810_seq40"
CANDIDATE_RUN="$ATTEMPT/candidate_run"
EVIDENCE="$ATTEMPT/evidence"
SELECTION="$SNAPSHOT/src/unified_autoresearch/selection/development_basins_64_v1.json"
PROTOCOL="$SNAPSHOT/src/unified_autoresearch/protocols/development_v1.json"

if [ -e "$ATTEMPT" ]; then
  echo "REFUSE_EXISTING_OUTPUT $ATTEMPT"
  exit 3
fi
mkdir -p "$EVIDENCE"

export PYTHONDONTWRITEBYTECODE=1
export PYTHONNOUSERSITE=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

echo "=== COMPLETE LINUX SAFETY TEST GATE ==="
set +e
cd "$SNAPSHOT"
PYTHONPATH="$SNAPSHOT/src" "$PYTHON" -m pytest src/unified_autoresearch/tests -q -p no:cacheprovider \
  --junitxml="$EVIDENCE/pytest.xml" 2>&1 | tee "$EVIDENCE/PYTEST_STDOUT.txt"
TEST_RC=${PIPESTATUS[0]}
set -e

"$PYTHON" - "$EVIDENCE/pytest.xml" "$TEST_RC" "$EVIDENCE/TEST_GATE.json" <<'PY'
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
  --monitor-reason "restricted 64-basin development reproduction; one predeclared candidate; no formal search" \
  | tee "$EVIDENCE/CANDIDATE_COMMAND_STDOUT.txt"

echo "=== INDEPENDENT REPRODUCTION EVIDENCE CHECK ==="
"$PYTHON" - "$ATTEMPT" "$SNAPSHOT" "$PACKAGE64" "$ELIGIBILITY" <<'PY'
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
test_gate = json.loads((evidence / "TEST_GATE.json").read_text(encoding="utf-8"))
package_gate = json.loads((evidence / "PACKAGE_GATE.json").read_text(encoding="utf-8"))
eligibility = json.loads(eligibility_path.read_text(encoding="utf-8"))

assert test_gate["candidate_launch_allowed"] is True
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
    group: {
        key: group_metrics[group][key] - value
        for key, value in expected.items()
    }
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
    "experiment_id": "hbv_lite_64_hpc_reproduction_20260810_seq40",
    "job_id": os.environ.get("SLURM_JOB_ID"),
    "host": socket.gethostname(),
    "candidate_id": candidate["candidate_id"],
    "test_gate": test_gate,
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
    "test_gate": summary["test_gate"],
    "basin_count": summary["basin_count"],
    "runtime_count": summary["runtime_count"],
    "independently_counted_denials": summary["independently_counted_denials"],
    "group_metrics": summary["group_metrics"],
    "windows_reference_cells_exact_match": summary["windows_reference_cells_exact_match"],
}, sort_keys=True))
PY

echo "=== COMPLETE ATTEMPT MANIFEST ==="
cd "$ATTEMPT"
find . -type f ! -path './evidence/MANIFEST.sha256' -print0 | sort -z | xargs -0 sha256sum > evidence/MANIFEST.sha256
sha256sum -c evidence/MANIFEST.sha256 >/dev/null
echo "manifest_entries=$(wc -l < evidence/MANIFEST.sha256)"
echo "manifest_check=ok"
echo "summary=$EVIDENCE/REPRODUCTION_SUMMARY.json"
echo "manifest=$EVIDENCE/MANIFEST.sha256"
echo "candidate_summary=$CANDIDATE_RUN/CANDIDATE_SUMMARY.json"
