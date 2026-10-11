#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
import json,re
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
versions={name:sorted(p.name for p in (parent/name).iterdir() if p.is_dir() and re.fullmatch(r'v[0-9]{3}',p.name)) for name in ('versions','execution')}
print(json.dumps({'parent_version_check':versions}))
if any(items and items[-1]!='v003' for items in versions.values()):
    raise SystemExit('PARENT_VERSION_CHANGE_REQUIRES_INTERFACE_REVIEW')
PY
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001/code/advance.py --root /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001 --parent /data1/home/sunyiq/hydrol85935_revision_20261008_001 --version v003
