"""Compare original predictions under explicit numeric backends; no training or attack search."""
import json
import sys
from pathlib import Path

ROOT = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
CODE = ROOT / 'versions/v002/code'
sys.path.insert(0, str(CODE))
import torch
from src.adversarial.scripts.revision_20261008.contracts import Workspace
from src.adversarial.scripts.revision_20261008.data import reference_std
from src.adversarial.scripts.revision_20261008.run import freeze, make_engine, runtime

torch.set_num_threads(4)
assert torch.cuda.is_available() and torch.cuda.device_count() == 1
output = ROOT / 'diagnostics/backend_v002'
output.mkdir(parents=True, exist_ok=False)
all_rows = []
default = (torch.backends.cudnn.enabled, torch.backends.cudnn.allow_tf32, torch.backends.cuda.matmul.allow_tf32)
for name, flags in [('default', default), ('no_tf32', (True, False, False)), ('no_cudnn', (False, False, False))]:
    torch.backends.cudnn.enabled, torch.backends.cudnn.allow_tf32, torch.backends.cuda.matmul.allow_tf32 = flags
    workspace = Workspace(output / name, ROOT / 'inputs_v001', CODE, ROOT / 'original_models', ROOT / 'versions/v002/DATA.sha256')
    fingerprint = freeze(workspace)
    reference = reference_std(workspace)
    for model in ('original_s100', 'original_s200', 'original_s300'):
        for basin in ('01022500', '02108000', '05120500', '09492400'):
            try:
                engine, identity, baseline = make_engine(workspace, model, basin, 'cuda:0', 256, reference)
                row = dict(backend=name, model=model, basin=basin, status='PASS', baseline=baseline)
                del engine
            except Exception as error:
                row = dict(backend=name, model=model, basin=basin, status='FAIL', error=str(error))
            row['manifest_sha256'] = fingerprint
            all_rows.append(row)
            print(json.dumps(row), flush=True)
    (output / (name + '_runtime.json')).write_text(json.dumps(runtime(), indent=2))
(output / 'results.json').write_text(json.dumps(all_rows, indent=2))
print('BACKEND_DIAGNOSIS_COMPLETE', flush=True)
