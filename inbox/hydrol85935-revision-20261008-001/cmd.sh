#!/usr/bin/env bash
set -eo pipefail
date -Is
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json
from pathlib import Path
base=Path('/data1/home/sunyiq/miniconda3/envs')
for env in sorted(base.iterdir()):
 if not env.is_dir():continue
 row={'environment':env.name,'path':str(env),'packages':{}}
 for name in ['torch','numpy','pandas','xarray','scipy','ruamel.yaml','pyyaml']:
  patterns=[name.replace('-','_')+'-*.dist-info/METADATA']
  for pattern in patterns:
   for path in env.glob('lib/python*/site-packages/'+pattern):
    for line in path.read_text(errors='replace').splitlines():
     if line.startswith('Version: '): row['packages'][name]=line[9:];break
 print(json.dumps(row),flush=True)
PY
