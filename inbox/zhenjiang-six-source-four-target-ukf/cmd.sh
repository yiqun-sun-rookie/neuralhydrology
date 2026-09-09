#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
printf '%s\n' '=== 2022_MATRIX_RESOURCE_PREFLIGHT ==='
date --iso-8601=seconds
hostname
sinfo -p hgpu2p -N -h -o '%N|%t|%c|%m|%G|%E'
squeue -u sunyiq -h -o '%i|%j|%T|%M|%D|%R'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import datetime, hashlib, json, os, pathlib, shutil
a=pathlib.Path('/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001')
b=pathlib.Path('/data1/home/sunyiq/zhenjiang_5s5t_stage_b_20260907_001')
new=pathlib.Path('/data1/home/sunyiq/zhenjiang_2022_matrix_20260909_001')
p=a/'contracts/stage_a_data_contract.json'
raw=p.read_bytes()
assert hashlib.sha256(raw).hexdigest()=='0e2cc530d5158cb9535862b10d6489436b73811c84a3d601579ed79de28155b3'
contract=json.loads(raw)
inputs=[]
for item in contract['files']:
    path=pathlib.Path(item['path'])
    st=path.stat()
    inputs.append({'path':str(path),'size':st.st_size,'registered_bytes':item['byte_count'],'is_symlink':path.is_symlink(),'regular_file':path.is_file()})
checkpoints=[]
for root in (a,b):
    stage='stage_a' if root==a else 'stage_b'
    for seed in (17,29,43):
        path=root/'runs'/stage/('seed_'+str(seed))/'best_checkpoint.pt'
        st=path.stat()
        checkpoints.append({'path':str(path),'size':st.st_size,'is_symlink':path.is_symlink()})
usage=shutil.disk_usage(new.parent)
print(json.dumps({'schema':'zhenjiang-2022-matrix-readonly-preflight-v1','time_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'new_root_exists':new.exists(),'new_root_is_symlink':new.is_symlink(),'free_bytes':usage.free,'input_metadata':inputs,'checkpoint_metadata':checkpoints,'formal_input_bytes_read':0,'checkpoint_bytes_read':0,'source_contract_sha256':hashlib.sha256(raw).hexdigest()},sort_keys=True))
assert not new.exists() and not new.is_symlink()
assert all(x['size']==x['registered_bytes'] and not x['is_symlink'] and x['regular_file'] for x in inputs)
assert all(not x['is_symlink'] for x in checkpoints)
PY
printf '%s\n' '=== 2022_MATRIX_RESOURCE_PREFLIGHT_COMPLETE ==='
