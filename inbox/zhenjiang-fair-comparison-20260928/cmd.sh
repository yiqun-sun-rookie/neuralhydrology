#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_FAIR_EXPORT'
from __future__ import annotations
import base64
from io import BytesIO
import hashlib
import json
import math
from pathlib import Path
from pathlib import PurePosixPath
import subprocess
import tarfile

root=Path('/data1/home/sunyiq/zhenjiang_fair_comparison_20260928_002')
job='229380'
sites=('nanjing','zhenjiang','jiangyin','xuliujing')
seeds=(17,29,43)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def canonical(value):
    return json.dumps(value,sort_keys=True,ensure_ascii=False,
                      separators=(',',':'),allow_nan=False).encode()

def raw_file(relative, limit=200_000_000):
    name=PurePosixPath(relative)
    if name.is_absolute() or '..' in name.parts:
        raise ValueError('path outside exclusive root')
    path=root.joinpath(*name.parts)
    if path.is_symlink() or not path.is_file() or path.stat().st_size>limit:
        raise ValueError('missing, linked or oversized registered file: '+relative)
    return path.read_bytes()

submitted=json.loads(raw_file('submission/submitted.json',8192))
if submitted['job_id']!=job or submitted['status']!='SUBMITTED_ONCE':
    raise ValueError('audit job identity differs')
account=subprocess.run(['sacct','-j',job,'-n','-P','--format=JobID,State,ExitCode,Elapsed'],
                       capture_output=True,text=True,timeout=15,check=False)
if account.returncode!=0 or len(account.stdout)>8192:
    raise ValueError('scheduler accounting unavailable')
lines=[line.split('|') for line in account.stdout.splitlines()]
if not any(parts[:3]==[job,'COMPLETED','0:0'] for parts in lines):
    raise ValueError('job has not completed successfully')
protocol_raw=raw_file('protocol.json',65536)
manifest_raw=raw_file('reports/training_manifest.json',65536)
complete_raw=raw_file('run/separate_available/complete.json',16384)
selection_raw=raw_file('run/separate_available/selections.json',65536)
protocol=json.loads(protocol_raw)
manifest=json.loads(manifest_raw)
complete=json.loads(complete_raw)
selections=json.loads(selection_raw)
if (protocol['remote_root']!=str(root) or complete['status']!='COMPLETE' or
    complete['models_complete']!=12 or complete['epoch_records']!=1212 or
    complete['protocol_sha256']!=sha(protocol_raw) or
    complete['manifest_sha256']!=sha(manifest_raw) or
    complete['selection_sha256']!=sha(selection_raw) or
    len(selections)!=12 or manifest['file_count']!=21):
    raise ValueError('twelve-model completion or identity differs')
for name,spec in manifest['files'].items():
    value=raw_file(name)
    if len(value)!=spec['bytes'] or sha(value)!=spec['sha256']:
        raise ValueError('sealed source changed: '+name)
by_key={(x['station'],x['seed']):x for x in selections}
if set(by_key)!={(site,seed) for site in sites for seed in seeds}:
    raise ValueError('selection group identities differ')
members={
    'protocol.json':protocol_raw,
    'reports/training_manifest.json':manifest_raw,
    'preflight/result.json':raw_file('preflight/result.json',65536),
    'reports/compute_decision.json':raw_file('reports/compute_decision.json',16384),
    'run/separate_available/attempt.json':raw_file('run/separate_available/attempt.json',16384),
    'run/separate_available/complete.json':complete_raw,
    'run/separate_available/selections.json':selection_raw,
    'submission/submitted.json':raw_file('submission/submitted.json',8192),
}
records_checked=hashes_checked=0
for site in sites:
    for seed in seeds:
        folder='run/separate_available/'+site+'/'+str(seed)+'/'
        actual_json={p.name for p in (root/folder).glob('epoch_*.json')}
        actual_pt={p.name for p in (root/folder).glob('epoch_*.pt')}
        expected_json={f'epoch_{epoch:03d}.json' for epoch in range(101)}
        expected_pt={f'epoch_{epoch:03d}.pt' for epoch in range(101)}
        if actual_json!=expected_json or actual_pt!=expected_pt:
            raise ValueError('epoch coverage differs: '+folder)
        records=[]
        for epoch in range(101):
            name=folder+f'epoch_{epoch:03d}.json'
            raw=raw_file(name,16384)
            record=json.loads(raw)
            if (record['scope'],record['station'],record['seed'],record['epoch']) != (
                    'separate_available',site,seed,epoch):
                raise ValueError('epoch identity differs: '+name)
            if not math.isfinite(record['selection_mae_m']):
                raise ValueError('nonfinite selection error')
            check=record['checkpoint']
            checkpoint=folder+f'epoch_{epoch:03d}.pt'
            if check['relative_path']!=checkpoint:
                raise ValueError('checkpoint path differs: '+name)
            weight=raw_file(checkpoint,10_000_000)
            if len(weight)!=check['size_bytes'] or sha(weight)!=check['sha256']:
                raise ValueError('checkpoint hash differs: '+checkpoint)
            records.append(record)
            members[name]=raw
            records_checked+=1
            hashes_checked+=1
        best=min(records,key=lambda x:x['selection_mae_m'])
        selected=by_key[site,seed]
        if (selected['selected_epoch']!=best['epoch'] or
            selected['selected_checkpoint']!=best['checkpoint'] or
            selected['selected_mae_m']!=best['selection_mae_m'] or
            selected['fixed_epoch_100_checkpoint']!=folder+'epoch_100.pt'):
            raise ValueError('selection does not follow full epoch record')
        for epoch in {best['epoch'],100}:
            name=folder+f'epoch_{epoch:03d}.pt'
            members[name]=raw_file(name,10_000_000)
audit={'status':'COMPLETE','job_id':job,'root':str(root),
       'epoch_records_checked':records_checked,
       'checkpoint_hashes_checked':hashes_checked,
       'source_files_checked':len(manifest['files']),
       'protocol_sha256':sha(protocol_raw),'manifest_sha256':sha(manifest_raw),
       'completion_sha256':sha(complete_raw),'selection_sha256':sha(selection_raw),
       'accounting':account.stdout.strip()}
if records_checked!=1212 or hashes_checked!=1212:
    raise ValueError('independent audit count differs')
members['remote_audit.json']=canonical(audit)
payload=BytesIO()
with tarfile.open(fileobj=payload,mode='w:gz',compresslevel=9) as archive:
    for name,value in sorted(members.items()):
        info=tarfile.TarInfo(name)
        info.size=len(value)
        info.mode=0o600
        archive.addfile(info,BytesIO(value))
bundle=payload.getvalue()
if len(bundle)>3_000_000:
    raise ValueError('audited retrieval bundle exceeds mailbox bound')
print('AUDIT '+json.dumps({**audit,'bundle_bytes':len(bundle),
                          'bundle_sha256':sha(bundle),'bundle_members':len(members)},sort_keys=True))
print('BUNDLE_BASE64 '+base64.b64encode(bundle).decode())
ZJ_FAIR_EXPORT
