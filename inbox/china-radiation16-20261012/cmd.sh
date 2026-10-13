#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - '241628' <<'PY'
import base64,gzip,hashlib,json,subprocess,sys
from pathlib import Path
entry=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2/projection_argument_entry_v1');patch=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2/projection_argument_repair_v1');job=sys.argv[1]
assert job.isdigit() and (entry/'OWN_PROJECTION_JOB_ID.txt').read_text().strip()==job
assert entry.is_dir() and not entry.is_symlink()
records={'job_id':job,'source_job_241367_failed_preserved':True}
for name,cmd in [('squeue',['squeue','-j',job,'-h','-o','%i|%j|%T|%R']),('sacct',['sacct','-j',job,'--noheader','--parsable2','--format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,NodeList,AllocTRES'])]:
    proc=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=12)
    assert len(proc.stdout)+len(proc.stderr)<=8192
    records[name]={'returncode':proc.returncode,'stdout':proc.stdout.decode(),'stderr':proc.stderr.decode()}
logs={}
for suffix in ['out','err']:
    p=entry/'logs'/('repair-'+job+'.'+suffix)
    data=p.read_bytes() if p.is_file() else b'MISSING'
    assert len(data)<=8192
    logs[suffix]=base64.b64encode(data).decode()
records['logs_base64']=logs
proof_path=patch/'PROJECTION_ARGUMENT_BYTE_PATCHES.json'
records['proof_exists']=proof_path.is_file()
if proof_path.is_file():
    assert not patch.is_symlink() and not proof_path.is_symlink()
    proof=proof_path.read_bytes();assert len(proof)<=65536
    compressed=gzip.compress(proof,mtime=0)
    records['proof_gzip_base64']=base64.b64encode(compressed).decode()
    records['proof_bytes']=len(proof);records['proof_sha256']=hashlib.sha256(proof).hexdigest()
encoded=json.dumps(records,separators=(',',':')).encode()
output=b'OWN_PROJECTION_CONTROL_BEGIN\n'+encoded+b'\nOWN_PROJECTION_CONTROL_END\nOWN_PROJECTION_READ_DONE\n'
assert len(output)<=60000
sys.stdout.buffer.write(output)
PY
