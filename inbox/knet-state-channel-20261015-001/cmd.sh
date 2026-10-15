#!/bin/bash
set -eo pipefail
PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 PYTHONUTF8=1 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_finetune_20261015_001 <<'READ_ONLY_PY'
import sys,json
from pathlib import Path
base=Path(sys.argv[1]);sys.path.insert(0,str(base))
from safe_io import read_checked
for rel in ['runs/02092500/attempt_001/stdout.log','runs/02092500/attempt_001/controller_started.json','runs/02092500/attempt_001/receipt.json','logs/diagnostic-242768_0.err']:
    path=base/rel
    print('FAILED_BASIN_EVIDENCE='+json.dumps(dict(path=rel,text=read_checked(path).decode('utf-8',errors='replace') if path.is_file() else None)))
READ_ONLY_PY
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_finetune_20261015_001/query_collect.py /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_finetune_20261015_001 242768
