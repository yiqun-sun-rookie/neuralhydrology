#!/bin/bash
set -o pipefail

ROOT=/data1/home/sunyiq/autoresearch64
PYTHON="$ROOT/.venv/bin/python"
AUTO="$ROOT/runs/unified_autoresearch/automatic_rehearsal_8x3_20260811_seq59"
SCALE="$ROOT/runs/unified_autoresearch/hbv_lite_64_hpc_reproduction_20260810_seq48"

echo "=== JOB PROVENANCE ==="
sacct -j 202321,202556 -X --format=JobID%12,JobName%20,NodeList%9,State%14,ExitCode%8,Elapsed%10,Start%20,End%20

echo "=== MANIFESTS ==="
for root in "$SCALE" "$AUTO"; do
  test -f "$root/evidence/MANIFEST.sha256" || { echo "HOLD missing_manifest=$root"; exit 20; }
  (cd "$root" && sha256sum -c evidence/MANIFEST.sha256 >/dev/null) || exit 21
  echo "root=$root manifest_check=ok entries=$(wc -l < "$root/evidence/MANIFEST.sha256") manifest_sha256=$(sha256sum "$root/evidence/MANIFEST.sha256" | awk '{print $1}')"
done

echo "=== PROMOTION-EVIDENCE COMPARISON ==="
"$PYTHON" - "$AUTO" "$SCALE" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

auto_root = Path(sys.argv[1])
scale_root = Path(sys.argv[2])
auto_evidence_path = auto_root / "evidence" / "REHEARSAL_EVIDENCE.json"
scale_evidence_path = scale_root / "evidence" / "REPRODUCTION_SUMMARY.json"
auto = json.loads(auto_evidence_path.read_text(encoding="utf-8"))
scale = json.loads(scale_evidence_path.read_text(encoding="utf-8"))
auto_candidate_path = auto_root / "rehearsal" / "candidates" / "hbv_lite" / "candidate" / "candidate-descriptor.json"
scale_candidate_path = scale_root / "candidate_run" / "candidate" / "candidate-descriptor.json"
auto_candidate = json.loads(auto_candidate_path.read_text(encoding="utf-8"))
scale_candidate = json.loads(scale_candidate_path.read_text(encoding="utf-8"))

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

assert auto["recommended_candidate_id"] == "hbv-lite-calibrated-v1"
assert scale["candidate_id"] == auto["recommended_candidate_id"]
assert auto["dependency_versions"] == scale["dependency_versions"] == {
    "numpy": "1.26.4",
    "pandas": "2.2.3",
    "pyarrow": "17.0.0",
}
assert auto_candidate["candidate_id"] == scale_candidate["candidate_id"]
assert auto_candidate["category"] == scale_candidate["category"]
assert auto_candidate["seed"] == scale_candidate["seed"] == 29
assert auto_candidate["dependencies"] == scale_candidate["dependencies"]
assert auto_candidate["allowed_reads"] == scale_candidate["allowed_reads"]
assert auto_candidate["outputs"] == scale_candidate["outputs"]
assert auto["independently_counted_denials"] == scale["independently_counted_denials"] == 0
assert scale["basin_count"] == 64
assert scale["registered_run_count"] == 4
assert scale["score_report_count"] == 2
assert scale["sealed_final_evaluation_read_or_scored"] is False
assert scale["fair_benchmark_scoring_program_run"] is False
assert scale["formal_basin_search_run"] is False
assert scale["baseline_outperformance_claimed"] is False

relative_files = sorted(scale["runtime_source_sha256"])
auto_snapshot = auto_root / "snapshot"
source_hash_comparison = {
    relative: {
        "automatic_rehearsal_sha256": sha256(auto_snapshot / relative),
        "scale_reproduction_sha256": scale["runtime_source_sha256"][relative],
        "equal": sha256(auto_snapshot / relative) == scale["runtime_source_sha256"][relative],
    }
    for relative in relative_files
}
all_runtime_source_hashes_equal = all(value["equal"] for value in source_hash_comparison.values())
assert all_runtime_source_hashes_equal

auto_mtime = auto_evidence_path.stat().st_mtime
scale_mtime = scale_evidence_path.stat().st_mtime
assert scale_mtime < auto_mtime

result = {
    "schema_version": "automatic_recommendation_scale_evidence_comparison_v1",
    "automatic_rehearsal": {
        "experiment_id": auto["experiment_id"],
        "job_id": auto["job_id"],
        "evidence_mtime_epoch_seconds": auto_mtime,
        "recommended_candidate_id": auto["recommended_candidate_id"],
        "eight_basin_median_mean_nse": auto["independently_recomputed_median_mean_nse"][auto["recommended_candidate_id"]],
    },
    "existing_scale_reproduction": {
        "experiment_id": scale["experiment_id"],
        "job_id": scale["job_id"],
        "evidence_mtime_epoch_seconds": scale_mtime,
        "candidate_id": scale["candidate_id"],
        "basin_count": scale["basin_count"],
        "all_basin_metrics": scale["group_metrics"]["all"],
        "standard_basin_metrics": scale["group_metrics"]["standard"],
        "unstable_basin_metrics": scale["group_metrics"]["unstable"],
    },
    "identity_checks": {
        "candidate_id_equal": True,
        "category_equal": True,
        "seed_equal": True,
        "dependencies_equal": True,
        "allowed_reads_equal": True,
        "outputs_equal": True,
        "all_runtime_source_hashes_equal": all_runtime_source_hashes_equal,
        "runtime_source_file_count": len(source_hash_comparison),
        "denied_event_counts_zero": True,
    },
    "source_hash_comparison": source_hash_comparison,
    "chronology": {
        "scale_evidence_predates_automatic_recommendation": True,
        "scale_evidence_lead_seconds": auto_mtime - scale_mtime,
    },
    "technical_scaleup_gate": "PASS",
    "prospective_independence_gate": "HOLD",
    "prospective_independence_reason": "The 64-basin result existed before the eight-basin automatic recommendation and therefore is not a fresh post-selection confirmation.",
}
print(json.dumps(result, sort_keys=True))
PY
echo "GO read_only_promotion_comparison=complete"
exit 0
