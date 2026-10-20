"""Only decrypt, deploy files and submit to Slurm on the login node."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tarfile
from datetime import datetime,timezone
from pathlib import Path

ROOT=Path('/data1/home/sunyiq/regge_experiments/REGGE-PQX03-FORECAST-OBJECTIVE-FACTORIAL/20261020-v01')

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main(archive,expected,plain_sha):
    assert sha(archive)==expected
    data=archive.read_bytes();assert data[:8]==b'RGEPQX03'
    size=int.from_bytes(data[8:10],'big');assert size==256
    transfer=ROOT.with_name(ROOT.name+'-transfer')
    password=subprocess.run(['openssl','pkeyutl','-decrypt','-inkey',str(transfer/'transfer_private.pem'),'-pkeyopt','rsa_padding_mode:oaep'],input=data[10:10+size],capture_output=True,check=True).stdout
    encrypted=transfer/(expected+'.aes')
    if not encrypted.exists():encrypted.write_bytes(data[10+size:])
    else:assert encrypted.read_bytes()==data[10+size:]
    plain=transfer/(plain_sha+'.tar.gz')
    if not plain.exists():
        r=subprocess.run(['openssl','enc','-d','-aes-256-cbc','-md','sha256','-pass','stdin','-in',str(encrypted)],input=password+b'\n',capture_output=True,check=True)
        assert hashlib.sha256(r.stdout).hexdigest()==plain_sha
        with plain.open('xb') as f:f.write(r.stdout)
        os.chmod(plain,0o600)
    assert sha(plain)==plain_sha
    receipt=ROOT/'receipts/submission_receipt.json'
    if ROOT.exists():
        if receipt.exists():
            print(receipt.read_text());subprocess.run(['squeue','-j',str(json.loads(receipt.read_text())['job_id'])]);return
        raise RuntimeError('Existing own root without confirmed submission: reconcile, never overwrite or blindly resubmit')
    ROOT.parent.mkdir(parents=True,exist_ok=True);ROOT.mkdir(exist_ok=False)
    with tarfile.open(plain,'r:gz') as tar:
        members=tar.getmembers()
        for m in members:
            assert m.isfile() and (ROOT/m.name).resolve().is_relative_to(ROOT.resolve()) and not (ROOT/m.name).exists(),m.name
        tar.extractall(ROOT,members=members)
    for name in ['logs','receipts','outputs']:(ROOT/name).mkdir(exist_ok=True)
    manifest=json.loads((ROOT/'payload_manifest.json').read_text())
    for name,value in manifest.items():assert sha(ROOT/name)==value,name
    script=ROOT/'job.slurm';assert b'\r' not in script.read_bytes() and '--mem' not in script.read_text() and '--gres' not in script.read_text()
    queue=subprocess.run(['squeue','-u','sunyiq','-o','%.18i %.24j %.10T %.40R'],capture_output=True,text=True,check=True)
    (ROOT/'receipts/existing_jobs_before.txt').write_text(queue.stdout)
    assert 'regge_pqx03' not in queue.stdout,'Own same-name active job: reconcile first'
    start=dict(utc=datetime.now(timezone.utc).isoformat(),command=['sbatch',str(script)],script_sha256=sha(script),payload_sha256=plain_sha,encrypted_payload_sha256=expected,root=str(ROOT))
    with (ROOT/'receipts/submission_started.json').open('x') as f:json.dump(start,f,indent=2)
    r=subprocess.run(start['command'],cwd=ROOT,capture_output=True,text=True);output=r.stdout+r.stderr
    (ROOT/'receipts/submission_stdout.txt').write_text(output);print(output,flush=True)
    matches=re.findall(r'Submitted batch job ([0-9]+)',output)
    assert r.returncode==0 and len(matches)==1,'Ambiguous submission; reconcile marker/stdout/scheduler'
    result=dict(start,status='submitted',job_id=int(matches[0]),returncode=r.returncode)
    with receipt.open('x') as f:json.dump(result,f,indent=2)
    print('PQX03_SUBMISSION',json.dumps(result),flush=True)
    subprocess.run(['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','-B',str(ROOT/'status.py')],check=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--archive',type=Path,required=True);p.add_argument('--sha256',required=True);p.add_argument('--plain-sha256',required=True);a=p.parse_args()
    main(a.archive,a.sha256,a.plain_sha256)
