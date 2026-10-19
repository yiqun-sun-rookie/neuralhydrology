#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_graice_shared_c01_20261019_001
old=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-c01-shared-20261019/payload/shared_author_c01_train_payload_v001.tar.gz
test ! -e "$root"
test -x "$old/venv/bin/python"
test -f "$old/venv/runtime_ready"
queue=$(timeout 30 squeue -h -u sunyiq -n id25_c01_shared_261019 -o '%i|%j|%T')
if test -n "$queue"; then printf '%s\n' "$queue"; echo EXISTING_JOB_NO_DEPLOYMENT; exit 1; fi
printf '%s  %s\n' '5574d9d64cd8ccd9a2cfa8d47e2552a7320a5379e8e8d047b6ad51d961d4fbee' "$payload" | sha256sum -c -
mkdir "$root"
mkdir -p "$root/logs" "$root/tmp" "$root/cache/cuda" "$root/attempts"
tar -xzf "$payload" -C "$root"
"$old/venv/bin/python" - "$root" "$old" <<'PYFILES'
import json
from pathlib import Path
import shutil
import sys
root,old=map(Path,sys.argv[1:])
for rid in json.loads((root/'package/scaler_manifest.json').read_text()):
    target=root/'scalers'/rid/'scalers.json'
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(old/'runs'/rid/'scalers.json',target)
PYFILES
base="$root/source_tree/results/25_global_flood_hierarchy"
mkdir -p "$base/regional_daily_storage_20261012_001/inputs"
mkdir -p "$base/regional_graice_author_matched_b04_20261016_001/retrieved_v001"
mkdir -p "$base/regional_graice_author_matched_b04_20261016_001/staging_v001/comparison_reference"
mkdir -p "$base/regional_daily_lstm_matched_b03_20261015_001/staging_v001"
ln -s "$old/inputs/inputs.npz" "$base/regional_daily_storage_20261012_001/inputs/inputs.npz"
ln -s "$root/scalers" "$base/regional_graice_author_matched_b04_20261016_001/retrieved_v001/runs"
ln -s "$old/predictions.npz" "$base/regional_graice_author_matched_b04_20261016_001/retrieved_v001/predictions.npz"
ln -s "$root/inputs/reference.npz" "$base/regional_graice_author_matched_b04_20261016_001/staging_v001/comparison_reference/reference.npz"
ln -s "$root/inputs/application_inputs.npz" "$base/regional_daily_lstm_matched_b03_20261015_001/staging_v001/application_inputs.npz"
echo DEPLOYED_WITH_EXISTING_RECEIPTS_NO_REPEATED_PREFLIGHT
bash "$root/ops/id25_submit_shared_train.sh" initial
