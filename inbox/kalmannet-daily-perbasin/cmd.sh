#!/usr/bin/env bash
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=37 purpose=readonly-maint-flag-reservation-diagnosis'
date -Is
hostname
printf '%s\n' 'training_submissions=0 runtime_submissions=0 task_file_writes=0 signals_sent=0 formal_evaluation_access=0'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import json
import subprocess

def query(label, args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=30, check=False)
    print(json.dumps({"query": label, "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}, ensure_ascii=False), flush=True)
    return result

node = query("exact_node", ["scontrol", "show", "node", "ngu202"])
query("node_state_reservation_name_reason", ["sinfo", "-h", "-N", "-n", "ngu202", "-o", "%N|%P|%T|%i|%E"])
records = subprocess.run(["scontrol", "-o", "show", "reservation"], text=True, capture_output=True, timeout=30, check=False)
print(json.dumps({"query": "reservation_inventory_status_only", "exit_code": records.returncode, "stderr": records.stderr}), flush=True)
if records.returncode == 0:
    lines = [line for line in records.stdout.splitlines() if "ReservationName=" in line]
    if len(lines) > 200:
        raise RuntimeError("Reservation count exceeds bounded read-only query")
    matches = 0
    for record in lines:
        fields = dict(item.split("=", 1) for item in record.split() if "=" in item)
        nodes = fields.get("Nodes", "")
        if not nodes or nodes in {"(null)", "NONE"}:
            continue
        expansion = subprocess.run(["scontrol", "show", "hostnames", nodes], text=True, capture_output=True, timeout=10, check=False)
        if expansion.returncode != 0:
            print(json.dumps({"query": "reservation_node_expansion_error", "reservation": fields.get("ReservationName"), "exit_code": expansion.returncode, "stderr": expansion.stderr}), flush=True)
            continue
        if "ngu202" in expansion.stdout.splitlines():
            matches += 1
            print(json.dumps({"query": "reservation_covering_exact_node", "record": record}), flush=True)
    print(json.dumps({"matching_reservation_count": matches}), flush=True)
query("own_jobs_on_exact_node", ["squeue", "-h", "-u", "sunyiq", "-w", "ngu202", "-o", "%i|%j|%T|%R"])
if node.returncode != 0 or records.returncode != 0:
    raise SystemExit(1)
print("READONLY_MAINT_RESERVATION_DIAGNOSIS_COMPLETE")
PY
