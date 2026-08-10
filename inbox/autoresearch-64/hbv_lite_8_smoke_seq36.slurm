#!/usr/bin/env bash
#SBATCH -J a64-hbv8-smoke
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH -t 00:30:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err

set -eo pipefail

ROOT=/data1/home/sunyiq/autoresearch64
PYTHON="$ROOT/.venv/bin/python"
RUNS="$ROOT/runs/unified_autoresearch"
SNAPSHOT="$RUNS/dlopen_timezone_fix_validation_20260809_seq24"
SOURCE64="$RUNS/development_source_real_64_hpc"
ATTEMPT="$RUNS/hbv_lite_8_hpc_smoke_20260810_seq36"
SOURCE8="$ATTEMPT/source_8"
PACKAGE8="$ATTEMPT/packages_8"
CANDIDATE_RUN="$ATTEMPT/candidate_run"
EVIDENCE="$ATTEMPT/evidence"
SELECTION="$SNAPSHOT/src/unified_autoresearch/selection/development_basins_v1.json"
PROTOCOL="$SNAPSHOT/src/unified_autoresearch/protocols/development_v1.json"

if [ -e "$ATTEMPT" ]; then
  echo "REFUSE_EXISTING_OUTPUT $ATTEMPT"
  exit 3
fi
mkdir -p "$SOURCE8" "$EVIDENCE"

export PYTHONDONTWRITEBYTECODE=1
export PYTHONNOUSERSITE=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

echo "=== BUILD EIGHT-BASIN DEVELOPMENT-ONLY SOURCE ==="
"$PYTHON" - "$SOURCE64" "$SOURCE8" "$SELECTION" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

import pandas as pd

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
selection_path = Path(sys.argv[3])

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

manifest_path = source / "SOURCE_MANIFEST.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
assert manifest["schema_version"] == "development_source_v1"
assert manifest["source_kind"] == "explicitly_pre_sliced_development_only"
assert manifest["date_bounds"] == ["1999-10-01", "2008-09-30"]
assert manifest["sealed_final_evaluation_present"] is False
assert set(manifest["files"]) == {"features.parquet", "targets.parquet", "static_attributes.json"}
for name, expected in manifest["files"].items():
    assert sha256(source / name) == expected, name

selection = json.loads(selection_path.read_text(encoding="utf-8"))
basins = [str(value).zfill(8) for value in selection["basins"]]
assert len(basins) == 8 and len(set(basins)) == 8

features = pd.read_parquet(source / "features.parquet")
targets = pd.read_parquet(source / "targets.parquet")
statics = json.loads((source / "static_attributes.json").read_text(encoding="utf-8"))
for frame in (features, targets):
    frame["basin"] = frame["basin"].astype(str).str.zfill(8)
    frame["date"] = pd.to_datetime(frame["date"], errors="raise")
    assert [frame["date"].min().strftime("%Y-%m-%d"), frame["date"].max().strftime("%Y-%m-%d")] == [
        "1999-10-01",
        "2008-09-30",
    ]

features = features.loc[features["basin"].isin(basins)].copy()
targets = targets.loc[targets["basin"].isin(basins)].copy()
assert set(features["basin"]) == set(basins)
assert set(targets["basin"]) == set(basins)
assert len(features) == 8 * 3288
assert len(targets) == 8 * 3288
selected_statics = {
    "schema_version": statics["schema_version"],
    "basins": {basin: statics["basins"][basin] for basin in basins},
}

features.to_parquet(destination / "features.parquet", index=False)
targets.to_parquet(destination / "targets.parquet", index=False)
(destination / "static_attributes.json").write_text(
    json.dumps(selected_statics, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
files = {
    name: sha256(destination / name)
    for name in ("features.parquet", "targets.parquet", "static_attributes.json")
}
output_manifest = {
    "schema_version": "development_source_v1",
    "source_kind": "explicitly_pre_sliced_development_only",
    "forcing_product": manifest["forcing_product"],
    "date_bounds": ["1999-10-01", "2008-09-30"],
    "sealed_final_evaluation_present": False,
    "files": files,
}
(destination / "SOURCE_MANIFEST.json").write_text(
    json.dumps(output_manifest, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
print(json.dumps({"basin_count": 8, "row_count": len(features), "source_manifest_sha256": sha256(destination / "SOURCE_MANIFEST.json")}, sort_keys=True))
PY

echo "=== BUILD FROZEN DEVELOPMENT PACKAGES ==="
PYTHONPATH="$SNAPSHOT/src" "$PYTHON" - "$SOURCE8" "$PACKAGE8" "$PROTOCOL" "$SELECTION" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

from unified_autoresearch.data.packages import build_development_packages

source = Path(sys.argv[1])
package = Path(sys.argv[2])
protocol = Path(sys.argv[3])
selection = Path(sys.argv[4])
manifest = build_development_packages(
    source_root=source,
    source_manifest_path=source / "SOURCE_MANIFEST.json",
    protocol_path=protocol,
    selection_path=selection,
    output_root=package,
)
assert len(manifest["basins"]) == 8
assert manifest["protocols"] == ["forward", "reverse"]
digest = hashlib.sha256((package / "PACKAGE_MANIFEST.json").read_bytes()).hexdigest()
print(json.dumps({"basin_count": 8, "protocols": manifest["protocols"], "package_manifest_sha256": digest}, sort_keys=True))
PY

echo "=== RUN ONE PREDECLARED HBV-LITE CANDIDATE ==="
cd "$ROOT"
PYTHONPATH="$SNAPSHOT/src" "$PYTHON" -u "$SNAPSHOT/src/unified_autoresearch/scripts/run_single_candidate.py" \
  --candidate hbv_lite \
  --dependencies cluster \
  --repo-root "$ROOT" \
  --package-root "$PACKAGE8" \
  --output-root "$CANDIDATE_RUN" \
  --monitor-sample-interval-seconds 1.0 \
  --monitor-reason "restricted eight-basin end-to-end sandbox smoke; one predeclared candidate" \
  | tee "$EVIDENCE/CANDIDATE_COMMAND_STDOUT.txt"

echo "=== INDEPENDENT EVIDENCE CHECK ==="
"$PYTHON" - "$ATTEMPT" "$SNAPSHOT" <<'PY'
import hashlib
import importlib.metadata
import json
import os
import socket
import sys
from pathlib import Path

attempt = Path(sys.argv[1])
snapshot = Path(sys.argv[2])
candidate_root = attempt / "candidate_run"
evidence = attempt / "evidence"

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

candidate_summary_path = candidate_root / "CANDIDATE_SUMMARY.json"
candidate_summary = json.loads(candidate_summary_path.read_text(encoding="utf-8"))
assert candidate_summary["candidate_id"] == "hbv-lite-calibrated-v1"
assert candidate_summary["basin_count"] == 8
assert candidate_summary["cell_count"] == 8
assert candidate_summary["registered_run_count"] == 4
assert candidate_summary["score_report_count"] == 2
assert candidate_summary["sealed_final_evaluation_read_or_scored"] is False
assert candidate_summary["fair_benchmark_scoring_program_run"] is False
assert candidate_summary["formal_basin_search_run"] is False

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

source_files = (
    "src/unified_autoresearch/candidates/catalog.py",
    "src/unified_autoresearch/candidates/implementations/hbv_lite.py",
    "src/unified_autoresearch/data/packages.py",
    "src/unified_autoresearch/runtime/bootstrap.py",
    "src/unified_autoresearch/runtime/dependencies.py",
    "src/unified_autoresearch/runtime/runner.py",
    "src/unified_autoresearch/scripts/run_single_candidate.py",
    "src/unified_autoresearch/selection/development_basins_v1.json",
    "src/unified_autoresearch/workflow/candidate_development.py",
)
summary = {
    "schema_version": "hbv_lite_8_hpc_smoke_v1",
    "experiment_id": "hbv_lite_8_hpc_smoke_20260810_seq36",
    "job_id": os.environ.get("SLURM_JOB_ID"),
    "host": socket.gethostname(),
    "candidate_id": candidate_summary["candidate_id"],
    "basin_count": candidate_summary["basin_count"],
    "cell_count": candidate_summary["cell_count"],
    "registered_run_count": candidate_summary["registered_run_count"],
    "score_report_count": candidate_summary["score_report_count"],
    "runtime_count": len(runtimes),
    "runtimes": runtimes,
    "access_log_count": len(access_paths),
    "access_event_count": access_event_count,
    "independently_counted_denials": independent_denials,
    "candidate_summary_sha256": sha256(candidate_summary_path),
    "package_manifest_sha256": sha256(attempt / "packages_8" / "PACKAGE_MANIFEST.json"),
    "source_manifest_sha256": sha256(attempt / "source_8" / "SOURCE_MANIFEST.json"),
    "runtime_source_sha256": {relative: sha256(snapshot / relative) for relative in source_files},
    "dependency_versions": {
        name: importlib.metadata.version(name) for name in ("numpy", "pandas", "pyarrow")
    },
    "sealed_final_evaluation_read_or_scored": False,
    "fair_benchmark_scoring_program_run": False,
    "formal_basin_search_run": False,
}
path = evidence / "SMOKE_SUMMARY.json"
with path.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(summary, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps({key: summary[key] for key in ("experiment_id", "job_id", "candidate_id", "basin_count", "runtime_count", "independently_counted_denials")}, sort_keys=True))
PY

echo "=== MANIFEST ==="
cd "$ATTEMPT"
find . -type f ! -path './evidence/MANIFEST.sha256' -print0 | sort -z | xargs -0 sha256sum > evidence/MANIFEST.sha256
sha256sum -c evidence/MANIFEST.sha256 >/dev/null
echo "manifest_entries=$(wc -l < evidence/MANIFEST.sha256)"
echo "manifest_check=ok"
echo "summary=$EVIDENCE/SMOKE_SUMMARY.json"
echo "manifest=$EVIDENCE/MANIFEST.sha256"
echo "candidate_summary=$CANDIDATE_RUN/CANDIDATE_SUMMARY.json"

