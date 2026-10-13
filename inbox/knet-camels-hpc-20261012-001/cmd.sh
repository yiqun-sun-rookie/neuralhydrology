#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'QUERY_OWN_R3'
import sys,json,runpy
from pathlib import Path
base=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/origins_041_20261013_001')
sys.path.insert(0,str(base))
from safe_io import read_checked
sub=json.loads(read_checked(base/'submission_r3.json'))
sys.argv=[str(base/'query_collect.py'),str(base),sub['job_id']]
runpy.run_path(str(base/'query_collect.py'),run_name='__main__')
QUERY_OWN_R3
