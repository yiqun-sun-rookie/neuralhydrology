#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
date --iso-8601=seconds
hostname
for node in ngu001 ngu004 ngu006 ngu007 ngu008 ngu010 ngu011; do
  scontrol show node "$node" -o
done
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import datetime,importlib.metadata,importlib.util,json,pathlib,platform
names=('torch','numpy','pandas','scipy','psutil','pytest')
versions={}
for name in names:
    try: versions[name]=importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError: versions[name]=None
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_2022_matrix_20260909_001')
print(json.dumps({'schema':'zhenjiang-matrix-package-metadata-v1','python':platform.python_version(),'versions':versions,'new_root_exists':root.exists(),'new_root_symlink':root.is_symlink(),'formal_input_reads':0,'checkpoint_reads':0,'numerical_modules_imported':False,'time_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()},sort_keys=True))
PY
