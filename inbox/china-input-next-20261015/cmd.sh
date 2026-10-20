#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
exec timeout --signal=TERM --kill-after=3s 180s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'C42_PREP'
"""HPC-only original mapping bytes plus isolated software and authorization probes."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import time
import traceback
from urllib.parse import urlparse
from urllib.request import build_opener,ProxyHandler,HTTPRedirectHandler,Request
import zlib

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_42_preparation_20261020_v1')
PAYLOAD_B64='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'
START=time.monotonic()
OWNED=False
DEPLOYMENT_ERROR=None

def save(name,value):
    raw=(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode()
    assert len(raw)<=131072
    with (ROOT/name).open('xb') as out:out.write(raw)

def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):return None

def deploy():
    global OWNED
    assert not ROOT.exists() and ROOT.parent.resolve(strict=True)==ROOT.parent
    ROOT.mkdir(mode=0o700)
    OWNED=True
    payload=json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True)))
    assert set(payload)=={'CONTRACT.json','probe_geology_42_environment_20261020_v1.py','probe_china_ee_authorization_20261020_v1.py'}
    identities={}
    for name,row in payload.items():
        raw=base64.b64decode(row['base64'],validate=True)
        assert len(raw)==row['bytes']<=65536 and hashlib.sha256(raw).hexdigest()==row['sha256']
        with (ROOT/name).open('xb') as out:out.write(raw)
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==row['sha256']
        identities[name]=row['sha256']
    save('DEPLOYMENT.json',dict(files=identities,server_utc=utc(),slurm_submissions=0))
    return json.loads((ROOT/'CONTRACT.json').read_bytes())

def maps(contract):
    opener=build_opener(ProxyHandler({}),NoRedirect());rows=[]
    for row in contract['mapping_files']:
        assert time.monotonic()-START<80
        url='https://api.github.com/repos/haozhen315/CCAM-China-Catchment-Attributes-and-Meteorology-dataset/git/blobs/'+row['git_blob_sha1']
        assert urlparse(url).hostname=='api.github.com'
        request=Request(url,headers={'Accept-Encoding':'identity','User-Agent':'china-geology-42-materials/1'})
        with opener.open(request,timeout=30) as response:
            assert response.status==200 and response.geturl()==url and response.headers.get('Content-Encoding','identity')=='identity'
            raw=response.read(65537);assert len(raw)<=65536
            declared=response.headers.get('Content-Length');assert declared is None or int(declared)==len(raw)
            headers=dict(response.headers)
        with (ROOT/(row['name']+'.response.json')).open('xb') as out:out.write(raw)
        document=json.loads(raw)
        assert document['sha']==row['git_blob_sha1'] and document['size']==row['bytes'] and document['encoding']=='base64'
        data=base64.b64decode(''.join(document['content'].split()),validate=True)
        assert len(data)==row['bytes'] and hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==row['git_blob_sha1']
        with (ROOT/row['name']).open('xb') as out:out.write(data)
        rows.append(dict(name=row['name'],bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),
            git_blob_sha1=row['git_blob_sha1'],url=url,response_bytes=len(raw),response_sha256=hashlib.sha256(raw).hexdigest(),headers=headers))
    save('MAP_FILES.json',dict(status='TWO_FIXED_ORIGINAL_MAPPING_FILES_SAVED',files=rows,source_gets=2,scientific_values_parsed=0))

def probe(program,path,seconds,name):
    env=dict(os.environ,PYTHONPATH=path,PYTHONDONTWRITEBYTECODE='1',CUDA_VISIBLE_DEVICES='',OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1')
    began=time.monotonic()
    try:
        result=subprocess.run(['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','-B',str(ROOT/program)],
            stdin=subprocess.DEVNULL,capture_output=True,env=env,timeout=seconds)
        assert len(result.stdout)<=65536 and len(result.stderr)<=65536
        value=json.loads(result.stdout) if result.returncode==0 else dict(status='PROBE_PROCESS_FAILED')
        assert isinstance(value,dict)
        # No raw child stdout/stderr is persisted: authorization errors can contain secrets.
        save(name,dict(exit_code=result.returncode,seconds_before_write=time.monotonic()-began,
            stdout_bytes=len(result.stdout),stderr_bytes=len(result.stderr),result=value))
        assert time.monotonic()-began<seconds
    except subprocess.TimeoutExpired:
        save(name,dict(exit_code=None,status='PROBE_TIMEOUT',seconds_before_write=time.monotonic()-began,
            raw_child_output_saved=False,authorization_validated=False))

def main():
    resource.setrlimit(resource.RLIMIT_AS,(512*1024**2,resource.getrlimit(resource.RLIMIT_AS)[1]))
    contract=deploy()
    assert contract['root']==str(ROOT)
    save('PREPARATION_STARTED.json',dict(server_utc=utc(),source_gets_max=2,slurm_submissions=0,pixel_values_read=0))
    try:maps(contract)
    except Exception as error:
        save('MAP_FAILURE.json',dict(error_type=type(error).__name__,error=str(error),partial_files_preserved=True,automatic_retries=0))
    probe('probe_geology_42_environment_20261020_v1.py',contract['gis_path'],20,'GIS_RESULT.json')
    probe('probe_china_ee_authorization_20261020_v1.py',contract['ee_path'],55,'AUTH_RESULT.json')
    assert sum(p.stat().st_size for p in ROOT.iterdir() if p.is_file())<1048576
    save('PREPARATION_RESULT.json',dict(status='ACTUAL_PREPARATION_CHECKS_SAVED',root=str(ROOT),server_utc=utc(),
        mapping_ready=(ROOT/'MAP_FILES.json').exists(),seconds_before_write=time.monotonic()-START,
        scientific_values_parsed=0,pixel_values_read=0,slurm_submissions=0,model_calls=0,training_calls=0,
        automatic_checks_enabled=False,scientific_input_accepted=False,prediction_approved=False))
    assert time.monotonic()-START<155

def frame():
    records={}
    for name in ['DEPLOYMENT.json','PREPARATION_STARTED.json','MAP_FILES.json','MAP_FAILURE.json','GIS_RESULT.json',
                 'AUTH_RESULT.json','PREPARATION_RESULT.json','PREPARATION_FAILURE.json']:
        path=ROOT/name
        if not OWNED or not path.is_file():records[name]=dict(present=False);continue
        raw=path.read_bytes();assert len(raw)<=131072
        records[name]=dict(present=True,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),base64=base64.b64encode(raw).decode())
    body=json.dumps(dict(root=str(ROOT),stage='C3_GEOLOGY_42_PREPARATION_V1',server_utc=utc(),records=records,
        root_created=OWNED,deployment_error_type=DEPLOYMENT_ERROR,
        slurm_submissions=0,model_calls=0,pixel_values_read=0,automatic_checks_enabled=False),separators=(',',':')).encode()
    assert len(body)<=1048576
    print('C42_PREP_BYTES='+str(len(body)))
    print('C42_PREP_SHA256='+hashlib.sha256(body).hexdigest())
    print('C42_PREP_ZLIB_BASE64='+base64.b64encode(zlib.compress(body)).decode())
    print('C42_PREP_DONE',flush=True)

if __name__=='__main__':
    try:main()
    except BaseException as error:
        DEPLOYMENT_ERROR=type(error).__name__
        if OWNED and not (ROOT/'PREPARATION_FAILURE.json').exists():
            save('PREPARATION_FAILURE.json',dict(error_type=type(error).__name__,partial_files_preserved=True,automatic_retries=0))
    frame()

C42_PREP
