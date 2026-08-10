#!/bin/bash
# ID29 seq=134: repair seq133 receipt quoting and seal Slurm preclosure job 202500 without redeployment.
set -euo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
CLOSURE="$ROOT/closure_20260810"
PREVIOUS="$CLOSURE/provenance/pre_strict_decision_seq133"
PROVENANCE_PAYLOAD="$CLOSURE/provenance/strict_decision_seq133_payload.tar.gz"
DEPLOYMENT_RECEIPT="$CLOSURE/provenance/strict_decision_seq133_deployment_receipt.json"
JOB_RECEIPT="$CLOSURE/provenance/preclosure_validation_seq133_job.txt"
JOB_ID="$(cat "$JOB_RECEIPT")"
STDOUT="$CLOSURE/logs/N22-preclosure-check_${JOB_ID}.out"
STDERR="$CLOSURE/logs/N22-preclosure-check_${JOB_ID}.err"
PRESERVED_STDOUT="$CLOSURE/provenance/preclosure_validation_${JOB_ID}.out"
PRESERVED_STDERR="$CLOSURE/provenance/preclosure_validation_${JOB_ID}.err"
VALIDATION_RECEIPT="$CLOSURE/provenance/preclosure_validation_${JOB_ID}_receipt.json"

echo "=== VERIFY SEQ133 DEPLOYMENT STATE ==="
test "$JOB_ID" = "202500"
test ! -e "$DEPLOYMENT_RECEIPT"
test ! -e "$VALIDATION_RECEIPT"
test ! -e "$PRESERVED_STDOUT"
test ! -e "$PRESERVED_STDERR"
sha256sum -c <<'SHA256_DEPLOYED'
a686e5e558a295c36da9efdc2e1588873132d8c984c052003115e8c5fa264a15  /data1/home/sunyiq/nearing2022_da/closure_20260810/provenance/strict_decision_seq133_payload.tar.gz
c4487ffb1a4ba151dbc782830fb6209e2eae62666fb0819179dad632fae351db  /data1/home/sunyiq/nearing2022_da/closure_20260810/provenance/pre_strict_decision_seq133/verify_registered_closure.py
17463a5ab783d024def54993b0d04cbd37a4f655fbfd4f696da57d7c5251cea8  /data1/home/sunyiq/nearing2022_da/closure_20260810/provenance/pre_strict_decision_seq133/run_server_preclosure_check.py
dd7819377de090baf9e7210216e8d62ac1fd12fa46d2eb8a59fa74c6a4372b67  /data1/home/sunyiq/nearing2022_da/closure_20260810/provenance/pre_strict_decision_seq133/local_contract_validation.json
25f0ad9ba2e9cf51c1bac3de15ef307a6a56f64adce35a9b70043abf6fd2a553  /data1/home/sunyiq/nearing2022_da/closure_20260810/provenance/pre_strict_decision_seq133/local_contract_validation_junit.xml
3b0caef6076d457e303864227e6748ab947e39da01c0c1faea15795807ce8945  /data1/home/sunyiq/nearing2022_da/src/29_nearing2022_da_ar/scripts/verify_registered_closure.py
4ed2cdf9994e37ff913ffbd7f4eb466fe24d0a49675bfdbd886dd5799aa8419b  /data1/home/sunyiq/nearing2022_da/src/29_nearing2022_da_ar/scripts/run_server_preclosure_check.py
84d43c8e0fedc1d43576467c8c9d6b07553e54a36a6959bde801581b0f02cf7e  /data1/home/sunyiq/nearing2022_da/src/29_nearing2022_da_ar/reference/local_contract_validation.json
6920a8bdd91d5e441d49754d2de16943153d487f0ee7d8b7a065784f5e7c970b  /data1/home/sunyiq/nearing2022_da/src/29_nearing2022_da_ar/reference/local_contract_validation_junit.xml
dd7819377de090baf9e7210216e8d62ac1fd12fa46d2eb8a59fa74c6a4372b67  /data1/home/sunyiq/nearing2022_da/src/29_nearing2022_da_ar/reference/local_contract_validation_pre_strict_decision_20260811.json
25f0ad9ba2e9cf51c1bac3de15ef307a6a56f64adce35a9b70043abf6fd2a553  /data1/home/sunyiq/nearing2022_da/src/29_nearing2022_da_ar/reference/local_contract_validation_junit_pre_strict_decision_20260811.xml
dc8c5a18b77d321b1a4ae6aba24315b16cb5a59e4fa2c3a6c99ae8de4ba2d6ed  /data1/home/sunyiq/nearing2022_da/test/test_nearing2022_reproduction_contract.py
SHA256_DEPLOYED

echo "=== REPAIR DEPLOYMENT RECEIPT ONLY ==="
python - "$ROOT" "$PROVENANCE_PAYLOAD" "$PREVIOUS" "$DEPLOYMENT_RECEIPT" "$JOB_ID" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys

root = Path(sys.argv[1])
payload = Path(sys.argv[2])
previous = Path(sys.argv[3])
receipt = Path(sys.argv[4])
job_id = sys.argv[5]

def record(path):
    data = path.read_bytes()
    return {"path": str(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

deployed_relative = [
    "src/29_nearing2022_da_ar/scripts/verify_registered_closure.py",
    "src/29_nearing2022_da_ar/scripts/run_server_preclosure_check.py",
    "src/29_nearing2022_da_ar/reference/local_contract_validation.json",
    "src/29_nearing2022_da_ar/reference/local_contract_validation_junit.xml",
    "src/29_nearing2022_da_ar/reference/local_contract_validation_pre_strict_decision_20260811.json",
    "src/29_nearing2022_da_ar/reference/local_contract_validation_junit_pre_strict_decision_20260811.xml",
]
payload_record = record(payload)
if payload_record["bytes"] != 19865 or payload_record["sha256"] != "a686e5e558a295c36da9efdc2e1588873132d8c984c052003115e8c5fa264a15":
    raise ValueError("Published payload changed")
result = {
    "schema": "nearing2022-strict-final-decision-deployment-v1",
    "mailbox_seq": 133,
    "receipt_repair_mailbox_seq": 134,
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "payload": payload_record,
    "previous_canonical_files": [record(path) for path in sorted(previous.iterdir())],
    "deployed_files": [record(root / relative) for relative in deployed_relative],
    "unchanged_contract_test": record(root / "test/test_nearing2022_reproduction_contract.py"),
    "validation_job_id": job_id,
    "result": "strict exact final-decision matcher, server self-check, 64-test receipt, and preserved prior bytes deployed",
}
temporary = receipt.with_name(receipt.name + ".tmp")
temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + chr(10), encoding="utf-8")
os.replace(temporary, receipt)
print(json.dumps(result, sort_keys=True))
PY

echo "=== VERIFY SLURM JOB 202500 ==="
ROW="$(sacct -n -X -P -j "$JOB_ID" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList | awk -F'|' -v job="$JOB_ID" '$1 == job {print; exit}')"
test -n "$ROW"
printf '%s
' "$ROW"
IFS='|' read -r OBS_JOB JOB_NAME STATE EXIT_CODE ELAPSED START END NODE_LIST <<< "$ROW"
test "$OBS_JOB" = "$JOB_ID"
test "$JOB_NAME" = "N22-preclosure-check"
test "$STATE" = "COMPLETED"
test "$EXIT_CODE" = "0:0"
test -f "$STDOUT"
test -f "$STDERR"
test ! -s "$STDERR"
cp -p "$STDOUT" "$PRESERVED_STDOUT.tmp"
cp -p "$STDERR" "$PRESERVED_STDERR.tmp"
mv "$PRESERVED_STDOUT.tmp" "$PRESERVED_STDOUT"
mv "$PRESERVED_STDERR.tmp" "$PRESERVED_STDERR"
cmp "$STDOUT" "$PRESERVED_STDOUT"
cmp "$STDERR" "$PRESERVED_STDERR"

echo "=== PARSE STRICT SELF-CHECK AND WRITE VALIDATION RECEIPT ==="
python - "$ROOT" "$STDOUT" "$STDERR" "$PRESERVED_STDOUT" "$PRESERVED_STDERR" "$DEPLOYMENT_RECEIPT" "$VALIDATION_RECEIPT" "$JOB_ID" "$ELAPSED" "$START" "$END" "$NODE_LIST" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys

root = Path(sys.argv[1])
stdout = Path(sys.argv[2])
stderr = Path(sys.argv[3])
preserved_stdout = Path(sys.argv[4])
preserved_stderr = Path(sys.argv[5])
deployment_receipt = Path(sys.argv[6])
receipt = Path(sys.argv[7])
job_id, elapsed, start, end, node_list = sys.argv[8:13]

def record(path):
    data = path.read_bytes()
    return {"path": str(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

text = stdout.read_text(encoding="utf-8")
start_json = text.index("{")
summary, _ = json.JSONDecoder().raw_decode(text[start_json:])
expected_strict = {
    "accepted": ["GO", "NO_GO"],
    "rejected": [
        {"gate": "GO", "register": "NO_GO"},
        {"gate": "NO_GO", "register": "GO"},
        {"gate": "GO", "register": "HOLD"},
    ],
}
if summary.get("strict_final_decision_match") != expected_strict:
    raise ValueError(f"Strict decision self-check changed: {summary.get('strict_final_decision_match')}")
if summary.get("registry_counts") != {"training": 46, "evaluation": 180, "hyperparameter": 660}:
    raise ValueError("Registry counts changed")
if summary.get("local_validation", {}).get("receipt_sha256") != "84d43c8e0fedc1d43576467c8c9d6b07553e54a36a6959bde801581b0f02cf7e":
    raise ValueError("Server did not validate the current local test receipt")
if summary.get("local_validation", {}).get("junit_sha256") != "6920a8bdd91d5e441d49754d2de16943153d487f0ee7d8b7a065784f5e7c970b":
    raise ValueError("Server did not validate the current JUnit XML")
if summary.get("data_manifests", {}).get("file_count") != 2131:
    raise ValueError("Data manifest file count changed")
if summary.get("data_manifests", {}).get("basin_count") != 531:
    raise ValueError("Data manifest basin count changed")
if summary.get("headline_recovery", {}).get("file_count") != 20:
    raise ValueError("Headline artifact binding changed")
result = {
    "schema": "nearing2022-preclosure-validation-receipt-v2",
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "slurm": {
        "job_id": job_id,
        "job_name": "N22-preclosure-check",
        "state": "COMPLETED",
        "exit_code": "0:0",
        "elapsed": elapsed,
        "start": start,
        "end": end,
        "node_list": node_list,
    },
    "strict_final_decision_match": expected_strict,
    "deployment_receipt": record(deployment_receipt),
    "source_stdout": record(stdout),
    "source_stderr": record(stderr),
    "preserved_stdout": record(preserved_stdout),
    "preserved_stderr": record(preserved_stderr),
    "closure_verifier": record(root / "src/29_nearing2022_da_ar/scripts/verify_registered_closure.py"),
    "server_checker": record(root / "src/29_nearing2022_da_ar/scripts/run_server_preclosure_check.py"),
    "local_validation_receipt": record(root / "src/29_nearing2022_da_ar/reference/local_contract_validation.json"),
    "local_validation_junit": record(root / "src/29_nearing2022_da_ar/reference/local_contract_validation_junit.xml"),
    "contract_test": record(root / "test/test_nearing2022_reproduction_contract.py"),
    "server_summary": summary,
}
temporary = receipt.with_name(receipt.name + ".tmp")
temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + chr(10), encoding="utf-8")
os.replace(temporary, receipt)
print(json.dumps(result, sort_keys=True))
PY

echo "=== FINAL SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$CLOSURE/aggregation/final_reproduction_gate.json"
test ! -e "$CLOSURE/aggregation/final_reproduction_differences.csv"
FAILURES="$(sacct -n -P -j 202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315,202500 --format=JobIDRaw,JobName,State,ExitCode | awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')"
printf '%s
' "$FAILURES"
test -z "$FAILURES"
sha256sum "$DEPLOYMENT_RECEIPT" "$VALIDATION_RECEIPT" "$PRESERVED_STDOUT" "$PRESERVED_STDERR"
