#!/bin/bash
set -eo pipefail

ATTEMPT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_64_hpc_reproduction_20260810_seq40
PYTHON=/data1/home/sunyiq/autoresearch64/.venv/bin/python

echo "=== EXACT NON-FILE FAILURE TRACEBACKS ==="
"$PYTHON" - "$ATTEMPT/evidence/pytest.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
needles = (
    "test_candidate_cannot_redirect_path_checks_by_replacing_os_path_helpers",
    "test_each_reference_candidate_trains_and_predicts_through_registered_runtime[conceptual_rainfall_runoff]",
    "test_registered_recovery_matches_a_clean_deterministic_training_run",
)
for case in root.findall(".//testcase"):
    name = case.attrib.get("name", "")
    if name not in needles:
        continue
    node = case.find("failure")
    if node is None:
        node = case.find("error")
    text = (node.attrib.get("message", "") + "\n" + (node.text or "")).strip()
    print(f"--- {case.attrib.get('classname')}::{name} ---")
    print(text[-6000:])
PY

echo "=== CANDIDATE WAS NOT LAUNCHED ==="
test ! -e "$ATTEMPT/candidate_run"
echo "candidate_run_absent=true"
