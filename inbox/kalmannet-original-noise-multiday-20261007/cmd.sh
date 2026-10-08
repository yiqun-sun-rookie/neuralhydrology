#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -X utf8 -B - <<'WHEEL_ACCESS'
import json, shutil, urllib.request
url = 'https://files.pythonhosted.org/packages/3a/d0/edc009c27b406c4f9cbc79274d6e46d634d139075492ad055e3d68445925/numpy-1.26.4-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl'
record = {'mode': 'read-only HEAD and disk metadata', 'url': url, 'downloaded_bytes': 0, 'scientific_model_runs': 0, 'modified_environment_files': 0}
try:
    with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=30) as handle:
        record.update(status=handle.status, content_length=handle.headers.get('Content-Length'))
except Exception as error:
    record.update(error_type=type(error).__name__, error=str(error))
space = shutil.disk_usage('/data1/home/sunyiq')
record.update(disk_free_bytes=space.free)
print('WHEEL_ACCESS_JSON=' + json.dumps(record), flush=True)
WHEEL_ACCESS
