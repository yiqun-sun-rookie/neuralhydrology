#!/bin/bash
# seq=440 只读: 成对重训所需文件在服务器上的部署清单
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== 需要的脚本是否在服务器上 ==="
for f in   src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm   src/29_nearing2022_da_ar/hpc/analyze_warmup_target_pair.slurm   src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py   src/29_nearing2022_da_ar/scripts/analyze_warmup_target_pair.py   src/29_nearing2022_da_ar/scripts/score_reproduction_matrix.py   src/29_nearing2022_da_ar/scripts/prepare_evaluation_run.py   src/29_nearing2022_da_ar/scripts/verify_registered_closure.py ; do
  if [ -f "$ROOT/$f" ]; then echo "OK   $(sha256sum "$ROOT/$f" | cut -c1-16)  $f"; else echo "MISSING                    $f"; fi
done
echo "=== 仿真参考结果(打分要用)是否存在 ==="
python3 - "$ROOT" <<'PY' 2>&1 | tail -3
import sys
from pathlib import Path
import csv
root=Path(sys.argv[1])
r=root/'src/29_nearing2022_da_ar/registry/experiment_registry.csv'
rows=list(csv.DictReader(open(r,newline='')))
m=[x for x in rows if x.get('exp_id')=='N22-TS-SIM-S0']
print('registry row found:', bool(m))
if m:
    rd=m[0].get('run_dir','')
    p=root/rd if not rd.startswith('/') else Path(rd)
    print('run_dir:', p)
    print('test_results.p exists:', (p/'test/model_epoch030/test_results.p').is_file())
PY
echo "=== 磁盘余量 ==="
df -h "$ROOT" | tail -1
