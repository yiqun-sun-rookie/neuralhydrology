#!/usr/bin/env bash
#SBATCH -J a64-hbv64-new
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
CAMELS_ROOT=/data1/home/sunyiq/neuralhydrology/data/camels_us
BUILDER_PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/payload/unseen64_builder_85ae470c_seq65.tar.gz
BUILDER_PAYLOAD_SHA256=__BUILDER_PAYLOAD_SHA256__
BUILDER_COMMIT=85ae470c9c08a62abd402f082ecc692cfe203294
RUNTIME_PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/payload/a64_gate_repair_seq46.tar.gz
RUNTIME_PAYLOAD_SHA256=6bedefb2538f979a5896d236a09eabd58e5823fe9575ef1bec85bbe84f43add9
ATTEMPT="$RUNS/hbv_lite_unseen_64_confirmation_20260811_seq65"
BUILDER="$ATTEMPT/builder_snapshot"
RUNTIME="$ATTEMPT/runtime_snapshot"
EVIDENCE="$ATTEMPT/evidence"
CANDIDATE_RUN="$ATTEMPT/candidate_run"
SOURCE="$ATTEMPT/development_source"
PACKAGE="$ATTEMPT/development_packages"
ELIGIBILITY="$ATTEMPT/BASIN_ELIGIBILITY.json"
SELECTION="$BUILDER/src/unified_autoresearch/selection/development_basins_confirmation_64_v1.json"
HISTORICAL_SELECTION="$RUNTIME/src/unified_autoresearch/selection/development_basins_64_v1.json"
PROTOCOL="$RUNTIME/src/unified_autoresearch/protocols/development_v1.json"
REGISTRY="$BUILDER/src/unified_autoresearch/evidence/PROSPECTIVE_CONFIRMATION_REGISTRY_20260811.json"

if [ -e "$ATTEMPT" ]; then
  echo "REFUSE_EXISTING_OUTPUT $ATTEMPT"
  exit 3
fi
mkdir -p "$BUILDER" "$RUNTIME" "$EVIDENCE"
exec > "$EVIDENCE/JOB_STDOUT.txt" 2> "$EVIDENCE/JOB_STDERR.txt"

export PYTHONDONTWRITEBYTECODE=1
export PYTHONNOUSERSITE=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

echo "=== VERIFY AND EXTRACT BUILDER AND CANDIDATE SNAPSHOTS ==="
test "$(sha256sum "$BUILDER_PAYLOAD" | awk '{print $1}')" = "$BUILDER_PAYLOAD_SHA256"
test "$(sha256sum "$RUNTIME_PAYLOAD" | awk '{print $1}')" = "$RUNTIME_PAYLOAD_SHA256"
tar -xzf "$BUILDER_PAYLOAD" -C "$BUILDER"
tar -xzf "$RUNTIME_PAYLOAD" -C "$RUNTIME"
test "$(sha256sum "$SELECTION" | awk '{print $1}')" = "630c0fe47e7aabbecd24bfe4a4900b7a3d71f31c314af29a4e863d0428efae1f"
test "$(sha256sum "$HISTORICAL_SELECTION" | awk '{print $1}')" = "3d75df6cfce527b8f6580a9dcfe0eacccb65c8bd7aae987ce23ead462ab00e53"
test "$(sha256sum "$REGISTRY" | awk '{print $1}')" = "4ea97009e28f43558a3897adc98758f88a239556048b7aa47d5794fc2488b924"
(cd "$BUILDER" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$EVIDENCE/BUILDER_SNAPSHOT_MANIFEST.sha256"
(cd "$RUNTIME" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$EVIDENCE/RUNTIME_SNAPSHOT_MANIFEST.sha256"

echo "=== VERIFY PREREGISTRATION AND FROZEN CANDIDATE IDENTITY ==="
"$PYTHON" - "$REGISTRY" "$RUNTIME" "$BUILDER_COMMIT" "$EVIDENCE/PREFLIGHT.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

registry_path = Path(sys.argv[1])
runtime = Path(sys.argv[2])
builder_commit = sys.argv[3]
output = Path(sys.argv[4])
registry = json.loads(registry_path.read_text(encoding="utf-8"))

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

assert registry["candidate_count"] == 1
assert registry["candidate"] == {
    "candidate_id": "hbv-lite-calibrated-v1",
    "category": "conceptual_rainfall_runoff",
    "seed": 29,
}
assert registry["changed_factor"] == "basin_set"
assert registry["confirmation_result_available_at_freeze"] is False
assert registry["historical_equivalent_result_known"] is True
assert registry["selection"]["result_dependent_inputs"] is False
assert registry["selection"]["historical_overlap_count"] == 0
assert registry["selection"]["rank_range"] == [65, 128]
assert all(value is False for value in registry["protected_boundaries"].values())
actual_runtime_hashes = {
    relative: sha256(runtime / relative)
    for relative in registry["candidate_runtime_source_sha256"]
}
assert actual_runtime_hashes == registry["candidate_runtime_source_sha256"]
summary = {
    "schema_version": "prospective_confirmation_preflight_v1",
    "builder_commit": builder_commit,
    "frozen_at": registry["frozen_at"],
    "candidate": registry["candidate"],
    "changed_factor": registry["changed_factor"],
    "selection": registry["selection"],
    "runtime_source_sha256": actual_runtime_hashes,
    "protected_boundaries": registry["protected_boundaries"],
}
with output.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(summary, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(summary, sort_keys=True))
PY

echo "=== TARGETED BUILDER TEST GATE ==="
cd "$BUILDER"
PYTHONPATH="$BUILDER/src" "$PYTHON" -m pytest \
  src/unified_autoresearch/tests/test_prospective_confirmation_selection.py \
  src/unified_autoresearch/tests/test_basin_selection.py \
  src/unified_autoresearch/tests/test_scaleup_64_selection.py \
  src/unified_autoresearch/tests/test_scaleup_64_data_base.py \
  -q -p no:cacheprovider --junitxml="$EVIDENCE/BUILDER_TESTS.xml" \
  | tee "$EVIDENCE/BUILDER_TESTS_STDOUT.txt"

echo "=== BUILD ISOLATED DEVELOPMENT-ONLY SOURCE AND PACKAGES ==="
PYTHONPATH="$BUILDER/src" "$PYTHON" "$BUILDER/src/unified_autoresearch/scripts/build_real_development_source.py" \
  --camels-root "$CAMELS_ROOT" \
  --static-table "$BUILDER/src/fair_benchmark/frozen/bundle/track0_statics.csv" \
  --protocol "$PROTOCOL" \
  --selection "$SELECTION" \
  --output-root "$SOURCE" \
  | tee "$EVIDENCE/BUILD_SOURCE_STDOUT.txt"
PYTHONPATH="$BUILDER/src" "$PYTHON" "$BUILDER/src/unified_autoresearch/scripts/build_real_development_packages.py" \
  --source-root "$SOURCE" \
  --protocol "$PROTOCOL" \
  --selection "$SELECTION" \
  --output-root "$PACKAGE" \
  | tee "$EVIDENCE/BUILD_PACKAGES_STDOUT.txt"
PYTHONPATH="$BUILDER/src" "$PYTHON" "$BUILDER/src/unified_autoresearch/scripts/classify_development_basins.py" \
  --package-root "$PACKAGE" \
  --output "$ELIGIBILITY" \
  | tee "$EVIDENCE/CLASSIFY_BASINS_STDOUT.txt"

echo "=== VERIFY NEW-BASIN PACKAGE BEFORE CANDIDATE LAUNCH ==="
"$PYTHON" - "$SOURCE" "$PACKAGE" "$ELIGIBILITY" "$SELECTION" "$HISTORICAL_SELECTION" "$PROTOCOL" "$EVIDENCE/PACKAGE_GATE.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

source_root = Path(sys.argv[1])
package_root = Path(sys.argv[2])
eligibility_path = Path(sys.argv[3])
selection_path = Path(sys.argv[4])
historical_path = Path(sys.argv[5])
protocol_path = Path(sys.argv[6])
output_path = Path(sys.argv[7])

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
historical = json.loads(historical_path.read_text(encoding="utf-8"))
protocol = json.loads(protocol_path.read_text(encoding="utf-8"))
expected = [str(value).zfill(8) for value in selection["basins"]]
old = [str(value).zfill(8) for value in historical["basins"]]

assert selection["selection_rank_range"] == [65, 128]
assert len(expected) == len(set(expected)) == 64
assert set(expected).isdisjoint(old)
assert source["schema_version"] == "development_source_v1"
assert source["source_kind"] == "explicitly_pre_sliced_development_only"
assert source["date_bounds"] == ["1999-10-01", "2008-09-30"]
assert source["sealed_final_evaluation_present"] is False
for relative, expected_hash in source["files"].items():
    assert sha256(source_root / relative) == expected_hash, relative
assert package["schema_version"] == "development_packages_v1"
assert package["basins"] == expected
assert package["protocols"] == ["forward", "reverse"]
assert package["development_protocols"] == protocol["development_protocols"]
assert package["source_manifest_sha256"] == sha256(source_manifest_path)
for relative, expected_hash in package["files"].items():
    assert sha256(package_root / relative) == expected_hash, relative
for windows in package["development_protocols"].values():
    for start, end in windows.values():
        assert "1999-10-01" <= start <= end <= "2008-09-30"
assert eligibility["package_manifest_sha256"] == sha256(package_manifest_path)
standard = [str(value).zfill(8) for value in eligibility["standard_basins"]]
unstable = [str(value).zfill(8) for value in eligibility["unstable_basins"]]
assert set(standard) | set(unstable) == set(expected)
assert set(standard).isdisjoint(unstable)
assert standard and unstable
summary = {
    "schema_version": "prospective_confirmation_package_gate_v1",
    "basin_count": 64,
    "historical_overlap_count": 0,
    "selection_rank_range": selection["selection_rank_range"],
    "date_bounds": source["date_bounds"],
    "sealed_final_evaluation_present": False,
    "source_manifest_sha256": sha256(source_manifest_path),
    "package_manifest_sha256": sha256(package_manifest_path),
    "package_file_count": len(package["files"]),
    "standard_basin_count": len(standard),
    "unstable_basin_count": len(unstable),
}
with output_path.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(summary, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(summary, sort_keys=True))
PY

echo "=== RUN THE ONE PREREGISTERED CANDIDATE ==="
cd "$ROOT"
PYTHONPATH="$RUNTIME/src" "$PYTHON" -u "$RUNTIME/src/unified_autoresearch/scripts/run_single_candidate.py" \
  --candidate hbv_lite \
  --dependencies cluster \
  --repo-root "$ROOT" \
  --package-root "$PACKAGE" \
  --output-root "$CANDIDATE_RUN" \
  --monitor-sample-interval-seconds 1.0 \
  --monitor-reason "one preregistered candidate on a disjoint development-only basin set" \
  | tee "$EVIDENCE/CANDIDATE_COMMAND_STDOUT.txt"

echo "=== INDEPENDENT RESULT AND SANDBOX AUDIT ==="
"$PYTHON" - "$ATTEMPT" "$RUNTIME" "$PACKAGE" "$ELIGIBILITY" "$REGISTRY" "$BUILDER_COMMIT" <<'PY'
import hashlib
import importlib.metadata
import json
import os
import socket
import statistics
import sys
from pathlib import Path

attempt = Path(sys.argv[1])
runtime = Path(sys.argv[2])
package_root = Path(sys.argv[3])
eligibility_path = Path(sys.argv[4])
registry_path = Path(sys.argv[5])
builder_commit = sys.argv[6]
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
eligibility = json.loads(eligibility_path.read_text(encoding="utf-8"))
registry = json.loads(registry_path.read_text(encoding="utf-8"))
package_gate = json.loads((evidence / "PACKAGE_GATE.json").read_text(encoding="utf-8"))
assert candidate["candidate_id"] == registry["candidate"]["candidate_id"]
assert candidate["basin_count"] == candidate["cell_count"] == 64
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
    assert value["process_exit_code"] == value["normalized_exit_code"] == 0
    assert value["denied_event_count"] == 0
    assert value["required_outputs_complete"] is True
    runtimes.append({"path": path.relative_to(attempt).as_posix(), **value})
access_paths = sorted(candidate_root.rglob("access.jsonl"))
assert len(access_paths) == 4
access_event_count = 0
denials = 0
for path in access_paths:
    events = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
    access_event_count += len(events)
    denials += sum(event.get("decision") == "deny" for event in events)
assert denials == 0

cells = candidate["cells"]
by_basin = {str(cell["basin"]).zfill(8): cell for cell in cells}
standard = [str(value).zfill(8) for value in eligibility["standard_basins"]]
unstable = [str(value).zfill(8) for value in eligibility["unstable_basins"]]
assert len(by_basin) == 64
assert set(by_basin) == set(standard) | set(unstable)

def metrics(basins):
    values = [float(by_basin[basin]["mean_nse"]) for basin in basins]
    return {
        "count": len(values),
        "median_mean_nse": statistics.median(values),
        "minimum_mean_nse": min(values),
        "maximum_mean_nse": max(values),
        "positive_mean_nse_count": sum(value > 0.0 for value in values),
    }

source_hashes = {
    relative: sha256(runtime / relative)
    for relative in registry["candidate_runtime_source_sha256"]
}
assert source_hashes == registry["candidate_runtime_source_sha256"]
summary = {
    "schema_version": "prospective_unseen_64_confirmation_v1",
    "experiment_id": registry["experiment_id"],
    "job_id": os.environ.get("SLURM_JOB_ID"),
    "host": socket.gethostname(),
    "builder_commit": builder_commit,
    "frozen_at": registry["frozen_at"],
    "candidate_id": candidate["candidate_id"],
    "candidate_seed": registry["candidate"]["seed"],
    "changed_factor": registry["changed_factor"],
    "basin_count": 64,
    "historical_overlap_count": package_gate["historical_overlap_count"],
    "registered_run_count": candidate["registered_run_count"],
    "score_report_count": candidate["score_report_count"],
    "runtime_count": len(runtimes),
    "runtimes": runtimes,
    "access_log_count": len(access_paths),
    "access_event_count": access_event_count,
    "independently_counted_denials": denials,
    "required_outputs_complete": [value["required_outputs_complete"] for value in runtimes],
    "process_exit_codes": [value["process_exit_code"] for value in runtimes],
    "normalized_exit_codes": [value["normalized_exit_code"] for value in runtimes],
    "runtime_statuses": [value["status"] for value in runtimes],
    "group_metrics": {
        "all": metrics(list(by_basin)),
        "standard": metrics(standard),
        "unstable": metrics(unstable),
    },
    "candidate_summary_sha256": sha256(candidate_summary_path),
    "package_manifest_sha256": sha256(package_root / "PACKAGE_MANIFEST.json"),
    "runtime_source_sha256": source_hashes,
    "runtime_source_identity_matches_preregistration": True,
    "dependency_versions": {
        name: importlib.metadata.version(name) for name in ("numpy", "pandas", "pyarrow")
    },
    "sealed_final_evaluation_read_or_scored": False,
    "fair_benchmark_scoring_program_run": False,
    "formal_basin_search_run": False,
    "baseline_outperformance_claimed": False,
}
output = evidence / "CONFIRMATION_SUMMARY.json"
with output.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(summary, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps({
    "experiment_id": summary["experiment_id"],
    "job_id": summary["job_id"],
    "candidate_id": summary["candidate_id"],
    "basin_count": summary["basin_count"],
    "historical_overlap_count": summary["historical_overlap_count"],
    "runtime_count": summary["runtime_count"],
    "independently_counted_denials": summary["independently_counted_denials"],
    "group_metrics": summary["group_metrics"],
}, sort_keys=True))
PY

echo "=== FINALIZE IMMUTABLE MANIFEST ==="
echo "summary=$EVIDENCE/CONFIRMATION_SUMMARY.json"
echo "manifest=$EVIDENCE/MANIFEST.sha256"
exec 1>&- 2>&-
cd "$ATTEMPT"
find . -type f ! -path './evidence/MANIFEST.sha256' -print0 | sort -z | xargs -0 sha256sum > evidence/MANIFEST.sha256
sha256sum -c evidence/MANIFEST.sha256 >/dev/null
