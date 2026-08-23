#!/usr/bin/env bash
set -o pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry2
STATUS_ROOT="$TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/status"
RESULT_ROOT="$TARGET/results/tukf19_hbv_rolling_origin_formal_execution_v1"
FIGURE_ROOT="$TARGET/artifacts/tukf17_hbv_rolling_origin_state_hydrology_update_v1/formal_verified_summary_v1"
ARCHIVE="$TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/tukf19_hpc_formal_result_retry2_v1.tar.gz"
ARCHIVE_MANIFEST="$ARCHIVE.sha256.json"

echo '=== TUKF19 FORMAL ACCOUNTING ==='
sacct -j 209845 -X -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,MaxRSS 2>&1 || true
squeue -j 209845 -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true

echo '=== TUKF19 FORMAL STATUS EVIDENCE ==='
for path in "$STATUS_ROOT/formal_submission.json" "$STATUS_ROOT/formal_started.json" "$STATUS_ROOT/formal_complete.json"; do
  echo "--- $path"
  if [[ -f "$path" ]]; then
    sha256sum "$path" 2>&1 || true
    cat "$path" 2>&1 || true
  else
    echo FILE_ABSENT
  fi
done
find "$STATUS_ROOT" -maxdepth 1 -type f -name 'formal_failure_*.json' -print -exec cat {} \; 2>&1 || true

echo '=== TUKF19 FORMAL LOGS ==='
for path in "$TARGET/logs/formal-209845.out" "$TARGET/logs/formal-209845.err"; do
  echo "--- $path"
  if [[ -f "$path" ]]; then
    sha256sum "$path" 2>&1 || true
    wc -c "$path" 2>&1 || true
    tail -n 200 "$path" 2>&1 || true
  else
    echo FILE_ABSENT
  fi
done

echo '=== TUKF19 FORMAL PACKAGE ==='
for path in "$ARCHIVE" "$ARCHIVE_MANIFEST"; do
  if [[ -f "$path" ]]; then
    sha256sum "$path" 2>&1 || true
    wc -c "$path" 2>&1 || true
  else
    echo "FILE_ABSENT $path"
  fi
done
if [[ -f "$ARCHIVE_MANIFEST" ]]; then
  cat "$ARCHIVE_MANIFEST" 2>&1 || true
fi

echo '=== TUKF19 REPRODUCIBILITY SUMMARY ==='
python -B - "$RESULT_ROOT" "$FIGURE_ROOT" "$STATUS_ROOT" "$ARCHIVE_MANIFEST" <<'PY'
import json
from pathlib import Path
import sys

result_root = Path(sys.argv[1])
figure_root = Path(sys.argv[2])
status_root = Path(sys.argv[3])
archive_manifest = Path(sys.argv[4])

def load(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None

registry = load(result_root / "registry.json")
verification = load(result_root / "independent_verification.json")
figures = load(figure_root / "manifest.json")
complete = load(status_root / "formal_complete.json")
package = load(archive_manifest)

summary = {
    "registry": None if registry is None else {
        "status": registry.get("status"),
        "experiment_id": registry.get("experiment_id"),
        "row_count": len(registry.get("rows", [])),
        "mechanism_classifications": registry.get("mechanism_classifications"),
        "primary_contrasts": registry.get("aggregates", {}).get("primary", {}).get("contrasts"),
        "crossed_readouts": registry.get("aggregates", {}).get("crossed"),
    },
    "independent_verification": None if verification is None else {
        "status": verification.get("status"),
        "checks": verification.get("checks"),
        "recomputed_test_readout_count": verification.get("recomputed_test_readout_count"),
        "recomputed_primary_clean_error_count": verification.get("recomputed_primary_clean_error_count"),
        "mechanism_classifications": verification.get("mechanism_classifications"),
    },
    "figures": figures,
    "formal_complete": complete,
    "package": None if package is None else {
        "deployment_id": package.get("deployment_id"),
        "scientific_experiment_id": package.get("scientific_experiment_id"),
        "archive_name": package.get("archive_name"),
        "archive_sha256": package.get("archive_sha256"),
        "archive_bytes": package.get("archive_bytes"),
        "member_count": package.get("member_count"),
        "payload_manifest_sha256": package.get("payload_manifest_sha256"),
    },
}
print(json.dumps(summary, indent=2, sort_keys=True))
PY

echo '=== TUKF19 FORMAL INVENTORY ==='
find "$RESULT_ROOT" -type f -printf '%P|%s\n' 2>&1 | sort || true
find "$FIGURE_ROOT" -type f -printf '%P|%s\n' 2>&1 | sort || true
echo TUKF19_FORMAL_AUDIT_SNAPSHOT_COMPLETE
exit 0
