#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import base64,gzip,hashlib,io,json,tarfile
from pathlib import Path
root=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2');output=root/'summary_request_transport_v1'
assert root.is_dir() and not root.is_symlink() and not output.exists() and not output.is_symlink()
for row in [{'name': 'hpc_summary_builder.py', 'bytes': 7726, 'sha256': 'a8f611321148881662a89fa30377403d8556c0189713c228e53baaf9f99ca931'}, {'name': 'hpc_radiation_reconstruct.py', 'bytes': 11565, 'sha256': 'd13ce1f0586c7f3a908b5dea9fd6e7a62fc1e614f3be4b8e2c841d4584b2e666'}, {'name': 'hpc_independent_radiation_review.py', 'bytes': 23689, 'sha256': '1d3d973207ba39886a17f89576bc01876db3b86cffcab00c6f1b7a57ee050676'}, {'name': 'summary_requests.sbatch', 'bytes': 1002, 'sha256': '69f1f8bd869fe7c61e7c69da88949b895caf8c04162c91a202aa22e82e3ead55'}, {'name': 'radiation_numerical.sbatch', 'bytes': 1016, 'sha256': 'a833a030e8fe300490a028a0718774113c716ee3e11772d25c5869c4e2c1784b'}, {'name': 'radiation_independent.sbatch', 'bytes': 1029, 'sha256': '15ead101196ed063d6280cb8b5212c5724663d7d17f7380dfbff732b1ab39146'}, {'name': 'FAILED_BATCH_INPUTS.json', 'bytes': 375103, 'sha256': '08dd954e645ec34442c874483e5e1fdbc3f862e72c2cb9e106e75a88ca301ae9'}, {'name': 'hpc_request_builder.py', 'bytes': 8819, 'sha256': '13aee1977d3ada5eda7e771338cbb5e4dfd4ecd31cd26d1400ae094b0e06712f'}, {'name': 'ALGORITHMS_RESPONSE_BODY.bin', 'bytes': 823173, 'sha256': '74d59ec8ff9194bcfa8f2e4bcdd8fed9422bb36ef10cf9d665a7482b3b80763d'}, {'name': 'ALGORITHMS_TRANSFER_RESULT.json', 'bytes': 429, 'sha256': 'a65e481c5bb8cc8eacc31bd240697775c6ad9579041c9f30dee064e1bb043695'}]:
    path=root/row['name'];assert path.is_file() and not path.is_symlink()
    data=path.read_bytes();assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256']
assert (root/'OWN_SUMMARY_JOB_ID.txt').read_text().strip()=='241367'
bundle=json.loads((root/'FAILED_BATCH_INPUTS.json').read_bytes())
allowed={'summary_'+r['basin_id']+'_'+r['label'] for r in bundle['failed_member_batches']};assert len(allowed)==32
requests=root/'summary_requests_v1';assert requests.is_dir() and not requests.is_symlink()
path=requests/'REQUEST_MANIFEST.json';manifest_raw=path.read_bytes();manifest=json.loads(manifest_raw)
assert manifest['kind']=='summary' and manifest['generated_on_hpc_job']=='241367' and manifest['local_numeric_operations']==0
assert manifest['source_requests']==len(manifest['requests'])==32
assert len({r['identity'] for r in manifest['requests']})==32 and {r['identity'] for r in manifest['requests']}==allowed
assert {p.name for p in requests.glob('*.json')}=={identity+'.json' for identity in allowed}|{'REQUEST_MANIFEST.json'}
original=[]
for row in manifest['requests']:
    assert row['kind']=='summary' and row['file']==row['identity']+'.json'
    path=requests/row['file'];assert path.is_file() and not path.is_symlink()
    data=path.read_bytes();assert len(data)==row['bytes']<=8388608 and hashlib.sha256(data).hexdigest()==row['sha256']
    original.append((row['file'],data))
    print('OWN_SUMMARY_SAVED_REQUEST_SHA256='+row['sha256']+' '+str(len(data))+' '+row['file'])
print('OWN_SUMMARY_FROZEN_RECORDS=32')
prepared=[]
for index,group in enumerate([original[:16],original[16:]],1):
    stream=io.BytesIO();items=group+[('REQUEST_MANIFEST.json',manifest_raw)]
    with tarfile.open(fileobj=stream,mode='w') as archive:
        for name,data in items:
            item=tarfile.TarInfo(name);item.size=len(data);item.mtime=0
            archive.addfile(item,io.BytesIO(data))
    assert len(stream.getvalue())<=67108864
    packet=gzip.compress(stream.getvalue(),compresslevel=6,mtime=0);assert len(packet)<=4194304
    prepared.append(('part%02d.tar.gz'%index,packet,[dict(name=name,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()) for name,data in items]))
assert sum(p.stat().st_size for p in root.parent.rglob('*') if p.is_file())+sum(len(packet) for name,packet,members in prepared)<=4294967296
output.mkdir()
packets=[]
for name,packet,members in prepared:
    with (output/name).open('xb') as stream:stream.write(packet)
    packets.append(dict(name=name,bytes=len(packet),sha256=hashlib.sha256(packet).hexdigest(),members=members))
report=dict(status='EXISTING_SUMMARY_REQUEST_BYTES_SPLIT_AND_SAVED',source_hpc_job_id='241367',
            source_hpc_job_failed_preserved=True,source_requests=0,new_generated_requests=0,new_cpu_jobs=0,
            scientific_functions_executed=0,record_count=32,request_manifest_sha256=hashlib.sha256(manifest_raw).hexdigest(),packets=packets)
with (output/'BYTE_TRANSPORT_RESULT.json').open('xb') as stream:stream.write((json.dumps(report,indent=2)+'\n').encode())
print('OWN_SUMMARY_BYTE_TRANSPORT_REPORT_BEGIN');print(json.dumps(report,indent=2));print('OWN_SUMMARY_BYTE_TRANSPORT_REPORT_END')
name,packet,members=prepared[0]
print('OWN_SUMMARY_PART1_SHA256='+hashlib.sha256(packet).hexdigest())
print('OWN_SUMMARY_PART1_BASE64_BEGIN');print(base64.b64encode(packet).decode());print('OWN_SUMMARY_PART1_BASE64_END')
print('OWN_SUMMARY_BYTE_PACK_DONE')
PY
