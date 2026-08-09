#!/bin/bash
set -euo pipefail

EVIDENCE=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/dlopen_timezone_fix_validation_20260809_seq24/evidence
PYTHON=/data1/home/sunyiq/autoresearch64/.venv/bin/python

"$PYTHON" - "$EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

evidence = Path(sys.argv[1])
summary = json.loads((evidence / "SUMMARY.json").read_text(encoding="utf-8"))
print(f"summary={evidence / 'SUMMARY.json'}")
print(f"manifest={evidence / 'MANIFEST.sha256'}")
print(f"diagnostic_complete={summary['diagnostic_complete']}")
print(f"manifest_entries={len((evidence / 'MANIFEST.sha256').read_text(encoding='utf-8').splitlines())}")
for relative in (
    "src/unified_autoresearch/runtime/bootstrap.py",
    "src/unified_autoresearch/runtime/runner.py",
):
    print(f"source_sha256[{relative}]={summary['runtime_source_sha256'][relative]}")

for probe in summary["probes"]:
    package = probe["package"]
    sandbox = probe["sandbox"]
    runtime = sandbox["runtime_result"]
    policy = json.loads(
        (evidence / "runs" / package / "logs" / "runtime-policy.json").read_text(encoding="utf-8")
    )
    events = [
        json.loads(line)
        for line in (evidence / "runs" / package / "logs" / "access.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
        if line
    ]
    denied = [event for event in events if event.get("decision") == "deny"]
    utc_reads = [
        event
        for event in events
        if event.get("operation") == "read" and event.get("path") == "/usr/share/zoneinfo/UTC"
    ]
    print(
        json.dumps(
            {
                "package": package,
                "declaration": probe["declaration"],
                "process_exit_code": sandbox["process_exit_code"],
                "normalized_exit_code": sandbox["normalized_exit_code"],
                "status": sandbox["status"],
                "denied_event_count": sandbox["denied_event_count"],
                "required_outputs_complete": runtime["required_outputs_complete"],
                "ctypes_dlopen_events": sandbox["ctypes_dlopen_events"],
                "system_timezone_read_paths": policy["dependency_initialization_system_read_paths"],
                "usr_share_utc_reads": utc_reads,
                "independently_counted_denials": len(denied),
            },
            sort_keys=True,
        )
    )
PY

(cd "$EVIDENCE" && sha256sum -c MANIFEST.sha256 >/dev/null)
echo "manifest_check=ok"
exit 0
