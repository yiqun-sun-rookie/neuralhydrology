#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'INITIAL_AUDIT'

import base64, hashlib, importlib.util, json, platform
from pathlib import Path
import torch
SPEC = json.loads(base64.b64decode('eyJtb2RlbHNfc2hhMjU2IjoiZGNhYTExNzJiZTAxNjZkNjRlODYxYWEyNzQ1MGJmZmYwMzRlODY5OGQ4ODIxNTA1MmI3Y2I4YjBiMGUyYWJmYyIsInJvb3RzIjp7ImJhc2UiOnsibWFuaWZlc3Rfc2hhMjU2IjoiMzIwYTQ1NTYyZDFmMmNlZDZiOGJhZjE2NWE3Nzc0MTU1OTZkMmVjZjFlNzAzMWM2NDcxMWRmMmY1ZjAyYTA2YyIsInJlZ2lzdHJ5X3NoYTI1NiI6ImJiYjA3YWY5MDQ3M2JhMTEzNjA0M2VjZWFhNWEwOWJiNmQwODVkYjE3MmQ3ZTM3ZTFmZTlhMTg1ZTExMTc5YmYiLCJyZW1vdGVfcm9vdCI6Ii9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfYXJjaGl0ZWN0dXJlX3NoYXJpbmdfMjAyNjA5MjlfMDAxIn0sImRpYWdub3N0aWMiOnsibWFuaWZlc3Rfc2hhMjU2IjoiY2QwNWIzNzU1ZTlmYTY3NWUxYzZkNDk5NWYwMDE2ZTY1ZDI3NzI4N2E5N2MyOGU4MmYyZDQyYmNiMzZkY2JiOSIsInJlZ2lzdHJ5X3NoYTI1NiI6Ijg0YzcwN2ZkNDBmMzdkOTU1NDE3YWRkMGE1YmQwOGM3ZWM4NTEyZWMyNjZmODI1MTA0MzNiMDk0YzExODU4YWQiLCJyZW1vdGVfcm9vdCI6Ii9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfdGFyZ2V0X3N0YXRlX2RpYWdub3N0aWNfMjAyNjA5MzBfMDAxIn19fQ=='))
torch.set_num_threads(2)
if torch.__version__ != '2.4.0': raise ValueError('original training library version differs')
def sha(raw): return hashlib.sha256(raw).hexdigest()
def state_sha(model):
    digest=hashlib.sha256()
    for name,value in sorted(model.state_dict().items()):
        array=value.detach().cpu().contiguous().numpy()
        digest.update(name.encode()); digest.update(str(array.dtype).encode())
        digest.update(json.dumps(list(array.shape),separators=(',',':')).encode())
        digest.update(array.tobytes())
    return digest.hexdigest()
checked=[]
for source, identity in SPEC['roots'].items():
    root=Path(identity['remote_root'])
    registry_raw=(root/'registry_frozen.json').read_bytes()
    manifest_raw=(root/'reports/training_manifest.json').read_bytes()
    if sha(registry_raw)!=identity['registry_sha256'] or sha(manifest_raw)!=identity['manifest_sha256']:
        raise ValueError('registered initial tensor sources differ')
    manifest=json.loads(manifest_raw)
    for name in ('src/comparison_models.py','src/train_one.py'):
        raw=(root/name).read_bytes()
        if sha(raw)!=manifest['files'][name]['sha256']: raise ValueError('sealed model source differs')
    loaded=importlib.util.spec_from_file_location('original_'+source,root/'src/comparison_models.py')
    module=importlib.util.module_from_spec(loaded); loaded.loader.exec_module(module)
    for row in json.loads(registry_raw)['runs']:
        torch.manual_seed(row['seed'])
        if row['architecture']=='old_encoder_decoder':
            model=module.LegacyEncoderDecoder(row['state_or_hidden_width'],row['output_dimensions'],dropout=0.0)
        elif source=='diagnostic':
            model=module.TargetStateProcess(('nanjing','zhenjiang','jiangyin','xuliujing').index(row['training_target']))
        else:
            model=module.ProcessState(row['state_or_hidden_width'])
        record=json.loads((root/'runs'/row['exp_id']/'epoch_000.json').read_bytes())
        digest=state_sha(model)
        if digest!=record['initial_state_sha256'] or digest!=record['checkpoint']['state_sha256']:
            raise ValueError('original-runtime initial state identity differs: '+row['exp_id'])
        checked.append({'source':source,'experiment_id':row['exp_id'],'initial_state_sha256':digest})
if len(checked)!=138: raise ValueError('combined initial audit coverage differs')
print('INITIAL_AUDIT '+json.dumps({'status':'PASS_ORIGINAL_RUNTIME_INITIAL_TENSOR_RECONSTRUCTION',
    'models_sha256':SPEC['models_sha256'],'runs_checked':len(checked),'torch':torch.__version__,
    'platform':platform.platform(),'training_or_data_read':False,'runs':checked},sort_keys=True))

INITIAL_AUDIT
