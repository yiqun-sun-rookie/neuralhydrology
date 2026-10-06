#!/usr/bin/env bash
set -euo pipefail
hostname
date -Is
command -v xbatch || true
command -v sbatch || true
sinfo -h -p hgpu2p -o '%P|%l|%G|%D|%T' || true
set +u
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
python - <<'PY'
import json,sys,pathlib,importlib.util
import torch,numpy,pandas,scipy
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/inputs/2017_2022')
files=[]
for role,stations in [('realtime_features',['datong','nanjing','zhenjiang','jiangyin','xuliujing','wusongkou']),('retrospective_targets',['nanjing','zhenjiang','jiangyin','xuliujing','wusongkou'])]:
    for station in stations:
        p=root/role/(station+'_'+role+'.csv')
        row={'path':str(p),'exists':p.is_file()}
        if p.is_file():
            row['bytes']=p.stat().st_size
            with p.open(encoding='utf-8-sig') as f: row['header']=f.readline().rstrip('\n')
        files.append(row)
print(json.dumps({'python':sys.version,'torch':torch.__version__,'numpy':numpy.__version__,'pandas':pandas.__version__,'scipy':scipy.__version__,'files':files,'evaluation_values_read':False}))
for p in pathlib.Path('/data1/home/sunyiq/miniconda3/envs').iterdir():
    if p.is_dir(): print('AVAILABLE_ENVIRONMENT',p.name)
PY
