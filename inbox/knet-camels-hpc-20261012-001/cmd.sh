#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/knet_camels_hpc_20261012_001
TRIAL=/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/correction_effect_20261013_001
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/knet-camels-hpc-20261012-001/payload/correction_effect_20261013_001/diagnostic.tar.gz
test -f "$ROOT/OWNER.txt"
test -f "$PAYLOAD"
printf '%s  %s\n' 00f286ac5873d634c11eb1dce7117a82ffef9855e974e60e7edf4144ef136971 "$PAYLOAD" | sha256sum -c -
mkdir "$TRIAL"
mkdir "$TRIAL/logs" "$TRIAL/receipts"
tar -xzf "$PAYLOAD" -C "$TRIAL"
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -B -c 'import json,hashlib,sys;from pathlib import Path;p=Path(sys.argv[1]);m=json.loads((p/"deployment_manifest.json").read_text());[(_ for _ in ()).throw(RuntimeError(x["path"])) for x in m["files"] if hashlib.sha256((p/x["path"]).read_bytes()).hexdigest()!=x["sha256"]];print(json.dumps({"status":"DEPLOYMENT_HASH_PASS","files":len(m["files"])}))' "$TRIAL"
sbatch "$TRIAL/diagnostic.slurm" | tee "$TRIAL/receipts/submission.txt"
