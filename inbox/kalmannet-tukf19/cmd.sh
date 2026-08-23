#!/usr/bin/env bash
set -o pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry2
RESULT_ROOT="$TARGET/results/tukf19_hbv_rolling_origin_formal_execution_v1"
STATUS_ROOT="$TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/status"
SMOKE="$TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/smoke/smoke_report.json"

echo '=== TUKF19 VERIFIED RESULT IDENTITY ==='
python -B - "$RESULT_ROOT" "$STATUS_ROOT" "$SMOKE" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

result_root = Path(sys.argv[1])
status_root = Path(sys.argv[2])
smoke_path = Path(sys.argv[3])

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def identity(path):
    return {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }

registry_path = result_root / "registry.json"
verification_path = result_root / "independent_verification.json"
failure_paths = sorted(status_root.glob("formal_failure_*.json"))
manifest_paths = sorted(
    path for path in result_root.rglob("*manifest*.json") if path.is_file()
)
registry = json.loads(registry_path.read_text(encoding="utf-8"))
verification = json.loads(verification_path.read_text(encoding="utf-8"))

contrast_summary = {}
for name, contrast in registry["aggregates"]["primary"]["contrasts"].items():
    contrast_summary[name] = {
        key: value
        for key, value in contrast.items()
        if key not in {"ratios", "per_pair_ratios", "by_lead"}
    }
    contrast_summary[name]["pair_count"] = len(contrast.get("per_pair_ratios", ()))
    contrast_summary[name]["lead_keys"] = sorted(contrast.get("by_lead", {}))

row_fields = sorted(registry["rows"][0]) if registry.get("rows") else []
readouts = sorted({row.get("readout_id") for row in registry.get("rows", ())})
all_files = [path for path in result_root.rglob("*") if path.is_file()]
report = {
    "files": {
        "registry": identity(registry_path),
        "independent_verification": identity(verification_path),
        "smoke_report": identity(smoke_path),
        "formal_failures": [identity(path) for path in failure_paths],
        "result_manifests": [identity(path) for path in manifest_paths],
    },
    "result_tree": {
        "file_count": len(all_files),
        "total_bytes": sum(path.stat().st_size for path in all_files),
        "history_count": len(list(result_root.rglob("methods/*/history.json"))),
        "array_count": len(list(result_root.rglob("*.npz"))),
    },
    "registry": {
        "status": registry.get("status"),
        "experiment_id": registry.get("experiment_id"),
        "row_count": len(registry.get("rows", ())),
        "row_fields": row_fields,
        "readouts": readouts,
        "primary_contrasts": contrast_summary,
        "mechanism_classifications": registry.get("mechanism_classifications"),
    },
    "verification": {
        "status": verification.get("status"),
        "checks": verification.get("checks"),
        "recomputed_test_readout_count": verification.get("recomputed_test_readout_count"),
        "recomputed_primary_clean_error_count": verification.get("recomputed_primary_clean_error_count"),
        "mechanism_classifications": verification.get("mechanism_classifications"),
    },
}
print(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
PY

echo '=== TUKF19 JOB TERMINAL CHECK ==='
sacct -j 209845 -X -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,MaxRSS 2>&1 || true
squeue -j 209845 -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true
echo TUKF19_VERIFIED_RESULT_IDENTITY_COMPLETE
exit 0
