#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -X utf8 -B - <<'READ_ONLY_ENVIRONMENT_INVENTORY'
import json
from pathlib import Path
base = Path('/data1/home/sunyiq/miniconda3')
roots = [base] + sorted(path for path in (base / 'envs').iterdir() if path.is_dir())
results = []
for root in roots:
    item = {'root': str(root), 'python_executable_exists': (root / 'bin/python').is_file(), 'packages': []}
    for directory in sorted((root / 'lib').glob('python*/site-packages')):
        for package in ('numpy', 'scipy'):
            for metadata in sorted(directory.glob(package + '-*.dist-info/METADATA')):
                fields = {}
                requirements = []
                for line in metadata.read_text(encoding='utf-8', errors='replace').splitlines():
                    if line.startswith(('Name: ', 'Version: ', 'Requires-Python: ')):
                        key, value = line.split(': ', 1)
                        fields[key] = value
                    elif line.startswith('Requires-Dist: numpy'):
                        requirements.append(line)
                item['packages'].append({'metadata': str(metadata), 'fields': fields, 'numpy_requirements': requirements})
    item['conda_python_records'] = [path.name for path in sorted((root / 'conda-meta').glob('python-*.json'))]
    results.append(item)
cache = [path.name for path in sorted((base / 'pkgs').glob('numpy-1.26*'))]
print('NUMERIC_ENVIRONMENT_JSON=' + json.dumps({'mode': 'read-only filesystem metadata', 'environments': results, 'numpy126_cache': cache, 'scientific_model_runs': 0, 'changed_environment_files': 0}), flush=True)
READ_ONLY_ENVIRONMENT_INVENTORY
