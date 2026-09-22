#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json
import os
import re
import shutil
import subprocess

root = "/data1/home/sunyiq/zhenjiang_update_budget_20260922_001"
query = subprocess.run(
    ["scontrol", "show", "partition", "hgpu2p", "-o"],
    capture_output=True, text=True, timeout=15, check=False)
maximum = re.search(r"(?:^|\s)MaxTime=([^\s]+)", query.stdout)
print(json.dumps({
    "probe": "zhenjiang-update-budget-20260922-seq-1",
    "remote_root_exists": os.path.lexists(root),
    "partition_query_returncode": query.returncode,
    "partition_max_time": maximum.group(1) if maximum else None,
    "partition_present": "PartitionName=hgpu2p" in query.stdout,
    "sbatch_present": shutil.which("sbatch") is not None,
    "python_exists": os.path.isfile(
        "/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python"),
    "stderr": query.stderr[:1000]
}, sort_keys=True))
PY
