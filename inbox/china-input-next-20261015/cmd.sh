#!/bin/bash
set -eo pipefail
umask 077
export CUDA_VISIBLE_DEVICES='' PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=5s 60s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_MEMFIX_SUBMIT'
import base64,hashlib,json,os,pathlib,re,subprocess
assert not os.environ.get('SLURM_JOB_ID') and os.environ.get('CUDA_VISIBLE_DEVICES')==''
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_login_tail_compute_parse_v1');submit=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_tail_parse_memfix_v1')
assert root.resolve(strict=True)==root and submit.parent.resolve(strict=True)==submit.parent and not submit.exists()
def read(name,limit):
 path=root/name;assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
 before=path.stat();assert 0<=before.st_size<=limit
 raw=path.read_bytes();after=path.stat()
 assert len(raw)==before.st_size==after.st_size and before.st_mtime_ns==after.st_mtime_ns
 return raw
for name,desc in {'SUBMISSION_RESULT.json': {'bytes': 258, 'sha256': 'a4fa1ddda0dec33efe0c68d0ed6176883bbbc2faf2806a4dfb0a87a48088f29b'}, 'LOGIN_CONTROL_RESULT.json': {'bytes': 772, 'sha256': '9322462a532a72bd181906ad6f9a16a6344521b1c80dc8dfd5f6ef6417d3ee10'}, 'TAIL_RESULT.json': {'bytes': 682, 'sha256': '44d4a92969399128a6939d1c0f1e551aedd3c80e682304cd3558cc02c8abb2f3'}}.items():
 raw=read(name,65536);assert len(raw)==desc['bytes'] and hashlib.sha256(raw).hexdigest()==desc['sha256']
old=json.loads(read('SUBMISSION_RESULT.json',65536))
assert old['status']=='SUBMISSION_UNCONFIRMED' and old['job_id'] is None and old['exit_code']==1 and old['stdout']==''
assert old['stderr']=='sbatch: error: Memory specification can not be satisfied\nsbatch: error: Batch job submission failed: Requested node configuration is not available\n'
assert json.loads(read('LOGIN_CONTROL_RESULT.json',65536))['accepted'] is True
tail=json.loads(read('TAIL_RESULT.json',65536))
assert tail['bytes']==2162746 and tail['sha256']=='4e2af2cb3ce03d8ad87835f66c8e9a2ec4f17246e4d5859d4a33585c1d403c0b'
path=root/'TAIL_BYTES.bin';assert path.resolve(strict=True)==path and path.is_file() and path.stat().st_size==2162746
for name in ['OWN_ATLAS_DIRECTORY_JOB_ID','LOGIN_CONTROL_FAILURE.json','TAIL_FAILURE.json',
 'CONTROL_STARTED.json','CONTROL_RESULT.json','CONTROL_FAILURE.json','HYDROATLAS_DIRECTORY_RESULT.json',
 'HYDROATLAS_DIRECTORY_FAILURE.json','HYDROATLAS_DIRECTORY_MEMBERS.json','directory_LAUNCH.json',
 'presence_LAUNCH.json','COMMON_SOURCE_PRESENCE_RESULT.json']:
 assert not (root/name).exists()
for name,desc in {'acquire_hydroatlas_tail_login_v1.py': {'bytes': 6503, 'sha256': '22b796c1c75771726bbf84cbdfb8b44ecc2df3f1b5bebbc85f9c417884568bc2'}, 'parse_hydroatlas_saved_tail_v1.py': {'bytes': 7234, 'sha256': '7ecf9f2164aac9677a2f79135cc3b737c5460d44f23fff4ad3b6e9e931ca934b'}, 'tail_login_control_v2.py': {'bytes': 1704, 'sha256': 'c803ed1f56789f67fea6f81d9d995b5c28523e7a94027f5ba3bf50a64a7d7e33'}, 'tail_compute_control_v2.py': {'bytes': 2724, 'sha256': '6a937a69ef2c92af7e1ef2558788afbc1a93dfcd492c5afabf3a516770bffd2e'}, 'tail_owned_stage_control_v2.py': {'bytes': 6046, 'sha256': 'ec3da0f7f94ab92dde3c663be2a5a5c993f168dea06810d12929a02f30ce8728'}, 'inspect_common_source_presence_v2.py': {'bytes': 5138, 'sha256': 'eeb74c9d601412199f89f282e3734072e53f6c1df60e28529758cbd802ab8c31'}, 'hydroatlas_pinned_transport_v1.py': {'bytes': 3325, 'sha256': '8ef3a4e49e2a58e5f223f67640994f295dbea659088417553df467e6d50b25ee'}, 'TAIL_CONTRACT.json': {'bytes': 1373, 'sha256': 'e3070acd66ffab461ed05242321a67225a0c784e3bdc35721a32fc591ef87b87'}, 'COMMON_PRESENCE_CONTRACT.json': {'bytes': 514, 'sha256': '7414ba8291313665b45b8ce86224676733d381e9d06f2ee4bf1bff1d097862fb'}, 'COMMON_HPC_PRESENCE_DRAFT_v2.json': {'bytes': 834137, 'sha256': '57451b019b12c5c7fcda233dec4a5135a2ea171bdf4391f401efb2a84761a805'}, 'DNS_RESOLUTION.json': {'bytes': 2796, 'sha256': 'f7419025eb61385d3f2680c02d01aa283cf25257eab888fffc7a69d400961f0f'}, 'parse.sbatch': {'bytes': 889, 'sha256': '19164fcd8242919596d86b306be6951a505fbe60e59c363b21c9d648138d9b92'}, 'ENTRY_TABLE.json': {'bytes': 1687, 'sha256': 'ca436ead8255804384cca9275f25eba35bbb119b37b716c1f59c54923addd30e'}}.items():
 raw=read(name,1048576);assert len(raw)==desc['bytes'] and hashlib.sha256(raw).hexdigest()==desc['sha256']
submit.mkdir(mode=0o700);(submit/'logs').mkdir(mode=0o700)
def save(name,value):
 raw=(json.dumps(value,indent=2)+'\n').encode();assert len(raw)<=65536
 with (submit/name).open('xb') as stream:stream.write(raw)
batch=base64.b64decode('IyEvYmluL2Jhc2gKI1NCQVRDSCAtLWpvYi1uYW1lPWNuX2F0bGFzX3BhcnNlCiNTQkFUQ0ggLS1wYXJ0aXRpb249aGdwdTJwCiNTQkFUQ0ggLS1leGNsdWRlPW5ndTAwMgojU0JBVENIIC0tbm9kZXM9MQojU0JBVENIIC0tbnRhc2tzPTEKI1NCQVRDSCAtLWNwdXMtcGVyLXRhc2s9MgojU0JBVENIIC0tdGltZT0wMDowNDowMAojU0JBVENIIC0tbm8tcmVxdWV1ZQojU0JBVENIIC0tb3V0cHV0PS9kYXRhMS9ob21lL3N1bnlpcS9jaGluYV9pbnB1dF9jb21wbGV0aW9uX2hwY18yMDI2MTAxNV8wMDEvaHlkcm9hdGxhc190YWlsX3BhcnNlX21lbWZpeF92MS9sb2dzL3BhcnNlLSVqLm91dAojU0JBVENIIC0tZXJyb3I9L2RhdGExL2hvbWUvc3VueWlxL2NoaW5hX2lucHV0X2NvbXBsZXRpb25faHBjXzIwMjYxMDE1XzAwMS9oeWRyb2F0bGFzX3RhaWxfcGFyc2VfbWVtZml4X3YxL2xvZ3MvcGFyc2UtJWouZXJyCnNldCAtZW8gcGlwZWZhaWwKdW1hc2sgMDc3CmV4cG9ydCBDVURBX1ZJU0lCTEVfREVWSUNFUz0nJwpleHBvcnQgT01QX05VTV9USFJFQURTPTEgT1BFTkJMQVNfTlVNX1RIUkVBRFM9MSBNS0xfTlVNX1RIUkVBRFM9MSBOVU1FWFBSX05VTV9USFJFQURTPTEKZXhwb3J0IFBZVEhPTkRPTlRXUklURUJZVEVDT0RFPTEgUFlUSE9OUEFUSD0nJwp1bGltaXQgLXYgNTI0Mjg4CmNkIC9kYXRhMS9ob21lL3N1bnlpcS9jaGluYV9pbnB1dF9jb21wbGV0aW9uX2hwY18yMDI2MTAxNV8wMDEvaHlkcm9hdGxhc19sb2dpbl90YWlsX2NvbXB1dGVfcGFyc2VfdjEKZXhlYyAvZGF0YTEvaG9tZS9zdW55aXEvbWluaWNvbmRhMy9lbnZzL25oX2ZpbmFsL2Jpbi9weXRob24gLUIgdGFpbF9jb21wdXRlX2NvbnRyb2xfdjIucHkK',validate=True)
assert len(batch)==858 and hashlib.sha256(batch).hexdigest()=='5668e3ef86a8a2f66f0e6213e8ff92f6bdadb12b93bdf6ae18a1eb643d25e458'
with (submit/'parse_memfix.sbatch').open('xb') as stream:stream.write(batch)
save('SUBMISSION_STARTED.json',dict(source_root=str(root),source_gets=0,source_tail_sha256=tail['sha256'],
 command=['sbatch','parse_memfix.sbatch'],automatic_retries=0,explicit_scheduler_memory_request=False))
try:result=subprocess.run(['sbatch','parse_memfix.sbatch'],cwd=submit,capture_output=True,timeout=25)
except BaseException as error:
 save('SUBMISSION_RESULT.json',dict(status='SUBMISSION_UNCONFIRMED',job_id=None,error_type=type(error).__name__,error=str(error)))
 raise
assert len(result.stdout)<=65536 and len(result.stderr)<=65536
match=re.fullmatch(rb'Submitted batch job ([0-9]+)\n',result.stdout)
if result.returncode!=0 or match is None:
 save('SUBMISSION_RESULT.json',dict(status='SUBMISSION_UNCONFIRMED',job_id=None,exit_code=result.returncode,
  stdout=result.stdout.decode('utf8',errors='replace'),stderr=result.stderr.decode('utf8',errors='replace')))
 raise RuntimeError('OWN_MEMFIX_SUBMISSION_UNCONFIRMED_NEVER_REPLAY')
job=match[1].decode()
with (submit/'OWN_ATLAS_DIRECTORY_JOB_ID').open('xb') as stream:stream.write((job+'\n').encode())
save('SUBMISSION_RESULT.json',dict(status='UNIQUE_JOB_SUBMITTED',job_id=job,exit_code=result.returncode,
 stdout=result.stdout.decode(),stderr=result.stderr.decode('utf8',errors='replace')))
print(result.stdout.decode(),end='',flush=True)
print('OWN_ATLAS_DIRECTORY_JOB_ID='+job,flush=True);print('OWN_ATLAS_DIRECTORY_SUBMIT_DONE',flush=True)
PY_MEMFIX_SUBMIT
