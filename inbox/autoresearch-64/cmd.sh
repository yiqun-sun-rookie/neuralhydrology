#!/bin/bash
set -eo pipefail

SNAPSHOT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/dlopen_timezone_fix_validation_20260809_seq24
ATTEMPT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_64_hpc_reproduction_20260810_seq40
PYTHON=/data1/home/sunyiq/autoresearch64/.venv/bin/python

echo "=== FAILED TEST GATE ==="
cat "$ATTEMPT/evidence/TEST_GATE.json"

echo "=== REQUIRED REPOSITORY-LEVEL FILES IN SNAPSHOT ==="
for path in \
  "$SNAPSHOT/src/fair_benchmark/frozen/bundle/track0_statics.csv" \
  "$SNAPSHOT/examples/06-Finetuning/531_basin_list.txt"; do
  if [ -f "$path" ]; then
    sha256sum "$path"
  else
    echo "MISSING $path"
  fi
done

echo "=== DISTINCT TEST FAILURE CAUSES ==="
"$PYTHON" - "$ATTEMPT/evidence/pytest.xml" <<'PY'
import collections
import re
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
records = []
for case in root.findall(".//testcase"):
    for kind in ("failure", "error"):
        node = case.find(kind)
        if node is None:
            continue
        text = (node.attrib.get("message", "") + "\n" + (node.text or "")).strip()
        missing = re.findall(r"FileNotFoundError:.*?'([^']+)'", text)
        last = next((line.strip() for line in reversed(text.splitlines()) if line.strip()), "")
        records.append((kind, case.attrib.get("classname"), case.attrib.get("name"), missing, last))

print(f"record_count={len(records)}")
missing_counts = collections.Counter(path for record in records for path in record[3])
for path, count in missing_counts.most_common():
    print(f"missing_path_count={count} path={path}")
last_counts = collections.Counter(record[4] for record in records)
for message, count in last_counts.most_common(12):
    print(f"terminal_message_count={count} message={message[:500]}")
for kind, classname, name, missing, last in records:
    if not missing:
        print(f"non_missing_file_case={kind} {classname}::{name} terminal={last[:500]}")
PY

echo "=== CANDIDATE WAS NOT LAUNCHED ==="
test ! -e "$ATTEMPT/candidate_run"
echo "candidate_run_absent=true"
