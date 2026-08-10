#!/bin/bash
set -euo pipefail

EVIDENCE=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/dlopen_timezone_fix_validation_20260809_seq24/evidence
PYTHON=/data1/home/sunyiq/autoresearch64/.venv/bin/python

echo "=== SCHEDULER ==="
sacct -j 202085 -X --format=JobID%12,JobName%20,State%14,ExitCode%8,Elapsed%10

test -f "$EVIDENCE/SUMMARY.json"
test -f "$EVIDENCE/MANIFEST.sha256"

"$PYTHON" - "$EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

evidence = Path(sys.argv[1])
summary = json.loads((evidence / "SUMMARY.json").read_text(encoding="utf-8"))
print(f"diagnostic_complete={summary['diagnostic_complete']}")
print(f"manifest_entries={len((evidence / 'MANIFEST.sha256').read_text(encoding='utf-8').splitlines())}")
for probe in summary["probes"]:
    package = probe["package"]
    sandbox = probe["sandbox"]
    runtime = sandbox["runtime_result"]
    events = [
        json.loads(line)
        for line in (evidence / "runs" / package / "logs" / "access.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
        if line
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
                "independently_counted_denials": sum(
                    event.get("decision") == "deny" for event in events
                ),
                "required_outputs_complete": runtime["required_outputs_complete"],
            },
            sort_keys=True,
        )
    )
PY

(cd "$EVIDENCE" && sha256sum -c MANIFEST.sha256 >/dev/null)
echo "manifest_check=ok"
echo "summary=$EVIDENCE/SUMMARY.json"
echo "manifest=$EVIDENCE/MANIFEST.sha256"
exit 0
