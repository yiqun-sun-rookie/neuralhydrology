#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=49 purpose=single-GPU-single-CPU-two-minute-resource-diagnostic-no-training'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_SUBMIT'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source'
sequence = 49
sha = lambda b: hashlib.sha256(b).hexdigest()
def require(value, message):
    if not value: raise RuntimeError(message)
def run(args, **kwargs):
    kwargs.setdefault('timeout', 45)
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
def emit(label, result):
    print(label, 'exit_code=' + str(result.returncode), flush=True)
    print(result.stdout.decode('utf-8'), end='', flush=True)
    print(result.stderr.decode('utf-8'), end='', file=sys.stderr, flush=True)
require(root.is_dir() and root.resolve() == root and not root.is_symlink(), 'registered root differs')
require(source.is_dir() and source.resolve() == source and not source.is_symlink(), 'source root differs')
def verify_source():
    archive = source.parent / 'daily_camels_knet_per_basin_pilots_v2.tar.gz'
    require(archive.is_file() and not archive.is_symlink(), 'archive missing or linked')
    data = archive.read_bytes()
    require(len(data) == 442374 and sha(data) == '737d7044e6c239d16a13d28ce1d7bd62fe8f58c6bd304ee89b3a681edc230c38', 'archive mismatch')
    mb = (source / 'bundle_manifest.json').read_bytes()
    require(sha(mb) == '39b0539bbdc14df2f443c3e6a548952c5ba2fe28bf650cc7be5b12f8bce0ad7f', 'manifest mismatch')
    manifest = json.loads(mb)
    actual = {}
    for path in source.rglob('*'):
        require(not path.is_symlink(), 'source contains link')
        if path.is_file(): actual[path.relative_to(source).as_posix()] = path
        else: require(path.is_dir(), 'source contains special member')
    require(len(actual) == 51 and set(actual) == set(manifest['member_sha256']) | {'bundle_manifest.json'}, 'source members differ')
    require(manifest['member_count'] == 50 and manifest['formal_evaluation_member_count'] == manifest['historical_evaluation_member_count'] == 0, 'member policy mismatch')
    for name, expected in manifest['member_sha256'].items():
        content = actual[name].read_bytes()
        require(sha(content) == expected and len(content) == manifest['member_size_bytes'][name], 'payload mismatch: ' + name)
    print('DEPLOYED_51_FILE_HASH_CHECK=PASS', flush=True)
verify_source()
import hashlib,json,pathlib
root=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source')
old_source=root/'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source'
sha=lambda b:hashlib.sha256(b).hexdigest()
def require(condition,message):
    if not condition: raise RuntimeError(message)
expected_runs=[
 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_A800_TRAIN3_SEQ13',
 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_08070200_A800_TRAIN1_SEQ18',
 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_A800_TRAIN1_SEQ24',
 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43_A800_TRAIN1_SEQ41']
failed=root/'runs'/expected_runs[-1]
def preserved_snapshot():
    require(sorted(p.name for p in (root/'runs').iterdir())==sorted(expected_runs),'run namespace drift')
    mb=(old_source/'bundle_manifest.json').read_bytes()
    require(sha(mb)=='5abaa07cfc00e2795a91a8cd70bb793e5cf362971fd04a2de44cbf3e15fa587f','old manifest drift')
    old_manifest=json.loads(mb)
    actual={p.relative_to(old_source).as_posix():p for p in old_source.rglob('*') if p.is_file()}
    require(set(actual)==set(old_manifest['member_sha256'])|{'bundle_manifest.json'},'old deployed inventory drift')
    for name,h in old_manifest['member_sha256'].items():
        require(not actual[name].is_symlink() and sha(actual[name].read_bytes())==h,'old source drift '+name)
    metadata={}
    for name in expected_runs:
        folder=root/'runs'/name
        require(folder.is_dir() and not folder.is_symlink(),'old run absent or linked')
        metadata[name]=[{'path':p.relative_to(folder).as_posix(),'size':p.stat().st_size,'mtime_ns':p.stat().st_mtime_ns}
                        for p in sorted(folder.rglob('*')) if p.is_file()]
    require((failed/'attempts/epoch_001.started.json').is_file(),'old failure marker missing')
    require((failed/'checkpoints/epoch_000.pt').is_file(),'old initial checkpoint missing')
    require(not (failed/'checkpoints/epoch_001.pt').exists() and not (failed/'completion.marker.json').exists(),'old failure was rewritten')
    return {'old_deployment_members':len(actual),'run_names':sorted(expected_runs),
            'old_run_file_metadata':metadata,
            'failed_run_file_sha256':{p.relative_to(failed).as_posix():sha(p.read_bytes()) for p in sorted(failed.rglob('*')) if p.is_file()}}

require(preserved_snapshot()==json.loads((source.parent/'pre_deploy_preserved_snapshot.json').read_text()),'old protected state differs from deployment baseline')
mb=(source/'bundle_manifest.json').read_bytes()
require(sha(mb)=='39b0539bbdc14df2f443c3e6a548952c5ba2fe28bf650cc7be5b12f8bce0ad7f','new manifest drift')
m=json.loads(mb)
actual={p.relative_to(source).as_posix():p for p in source.rglob('*') if p.is_file()}
require(set(actual)==set(m['member_sha256'])|{'bundle_manifest.json'},'new source inventory differs')
require(all(not p.is_symlink() and sha(p.read_bytes())==m['member_sha256'][n] for n,p in actual.items() if n!='bundle_manifest.json'),'new source hash drift')
require(len((source.parent/'daily_camels_knet_per_basin_pilots_v2.tar.gz').read_bytes())==442374 and sha((source.parent/'daily_camels_knet_per_basin_pilots_v2.tar.gz').read_bytes())=='737d7044e6c239d16a13d28ce1d7bd62fe8f58c6bd304ee89b3a681edc230c38','new archive drift')
print(json.dumps({'status':'HISTORYFIX1_PROTECTED_REMOTE_INTEGRITY_PASS','new_source_files':len(actual),'old_run_count':4,'old_failed_job_id':223514,'old_failure_preserved':True,'formal_access_count':0}),flush=True)

old_runtime=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907/historyfix1_runtime_seq44')
old_runtime_texts={"pre_submit_baseline.json":{"bytes":1613,"sha256":"616a5770539b7db84d9130cc25faf45d3a0f52aa02be0ee1244bbd6746783944"},"submission_receipt.json":{"bytes":368,"sha256":"24a1fc985979846c1a046dbf8d3b35372a5d1a46f8bd3bb8a1521839aec570a9"},"runtime_gate.sh":{"bytes":15609,"sha256":"5776c70ee3b11d0d60ca96daa0bfb77a3dd2e1a6c9d934939d207e5da31001c8"},"slurm-223532.stdout":{"bytes":4735,"sha256":"6dd491359bd074cc714bc2a01317c413a011493ed88067d88c8644c57a4764e3"},"slurm-223532.stderr":{"bytes":2114,"sha256":"4efc4169574534322422c18008aadf82b813ae75ebb8b3127313c23309a0dca3"},"history_binding_pytest.stdout":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"history_binding_pytest.stderr":{"bytes":2114,"sha256":"4efc4169574534322422c18008aadf82b813ae75ebb8b3127313c23309a0dca3"},"test_support/test_support_manifest.json":{"bytes":18958,"sha256":"59c91069fae4a880e559546c0c370b9fbedbd1ee716b6731ac28cd6b75f79d41"},"gate_04105700.stdout":{"bytes":866,"sha256":"9f684ee9b86c6903cb7c42ae7bfdde643ceaa01cdb76ccdca4ac0a90897fa6e6"},"gate_04105700.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_08070200.stdout":{"bytes":869,"sha256":"ac6605fd9450a82ae11c16339faeb7d0521631c1f10c025c6ee8354c35e52591"},"gate_08070200.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_09035800.stdout":{"bytes":868,"sha256":"dac90bcb54fd64af967e7894252eaad29dc2ed4a90015ea755b273ea6a68360b"},"gate_09035800.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}}
old_smb=(old_runtime/'test_support/test_support_manifest.json').read_bytes()
require(sha(old_smb)=='59c91069fae4a880e559546c0c370b9fbedbd1ee716b6731ac28cd6b75f79d41','failed runtime support manifest changed')
old_sm=json.loads(old_smb)
expected_old_runtime=set(old_runtime_texts)|{'isolated_pytest_support.tar.gz'}|{'test_support/'+n for n in old_sm['member_sha256']}
actual_old_runtime={p.relative_to(old_runtime).as_posix():p for p in old_runtime.rglob('*') if p.is_file()}
require(set(actual_old_runtime)==expected_old_runtime,'failed runtime file set changed')
for name,item in old_runtime_texts.items():
    p=actual_old_runtime[name];data=p.read_bytes()
    require(not p.is_symlink() and len(data)==item['bytes'] and sha(data)==item['sha256'],'failed runtime text changed: '+name)
for name,h in old_sm['member_sha256'].items():
    p=actual_old_runtime['test_support/'+name];require(not p.is_symlink() and sha(p.read_bytes())==h,'failed test support changed')
old_archive=(old_runtime/'isolated_pytest_support.tar.gz').read_bytes()
require(len(old_archive)==397296 and sha(old_archive)=='e485003651d55dac384f69cd11819300375fecb7ef0a2fe406c3857c0dc8d954','failed runtime archive changed')
require(not (old_runtime/'history_binding_junit.xml').exists() and not (old_runtime/'synthetic_tmp').exists(),'failed runtime was retried or repaired in place')
print(json.dumps({'status':'OLD_RUNTIME_223532_FAILURE_PRESERVED','frozen_text_files':14,'all_files':len(actual_old_runtime),'original_test_support_files':135,'synthetic_tests_started_in_old_job':0,'synthetic_toy_updates_actual_in_old_job':0}),flush=True)

import base64, datetime
probe_bytes=base64.b64decode('IyEvdXNyL2Jpbi9lbnYgcHl0aG9uMwoiIiJCb3VuZGVkLCByZWFkLW9ubHkgc25hcHNob3Qgb2YgdGhpcyBTbHVybSBhbGxvY2F0aW9uOyBubyBDVURBIGNvbnRleHQuIiIiCmltcG9ydCBiYXNlNjQKaW1wb3J0IGRhdGV0aW1lCmltcG9ydCBoYXNobGliCmltcG9ydCBqc29uCmltcG9ydCBvcwppbXBvcnQgcGF0aGxpYgppbXBvcnQgc3RhdAppbXBvcnQgc3VicHJvY2VzcwoKTUFYX1NURE9VVCA9IDI2MjE0NApNQVhfU1RERVJSID0gNjU1MzYKRU5WX0FMTE9XTElTVCA9ICgKICAgICJTTFVSTV9KT0JfSUQiLCAiU0xVUk1fSk9CX0dQVVMiLCAiU0xVUk1fU1RFUF9HUFVTIiwKICAgICJTTFVSTV9DUFVTX1BFUl9UQVNLIiwgIlNMVVJNX0pPQl9OT0RFTElTVCIsICJDVURBX1ZJU0lCTEVfREVWSUNFUyIsCikKCgpkZWYgYnl0ZXNfcmVjb3JkKGRhdGEpOgogICAgcmV0dXJuIHsKICAgICAgICAiYnl0ZXMiOiBsZW4oZGF0YSksCiAgICAgICAgInNoYTI1NiI6IGhhc2hsaWIuc2hhMjU2KGRhdGEpLmhleGRpZ2VzdCgpLAogICAgICAgICJiYXNlNjQiOiBiYXNlNjQuYjY0ZW5jb2RlKGRhdGEpLmRlY29kZSgiYXNjaWkiKSwKICAgIH0KCgpkZWYgZW1pdCh2YWx1ZSk6CiAgICBwcmludChqc29uLmR1bXBzKHZhbHVlLCBzb3J0X2tleXM9VHJ1ZSksIGZsdXNoPVRydWUpCgoKZGVmIGNvbW1hbmQobGFiZWwsIGFyZ3YpOgogICAgc3RhcnRlZCA9IGRhdGV0aW1lLmRhdGV0aW1lLm5vdyhkYXRldGltZS50aW1lem9uZS51dGMpLmlzb2Zvcm1hdCgpCiAgICByZWNvcmQgPSB7InN0YWdlIjogbGFiZWwsICJhcmd2IjogYXJndiwgInRpbWVvdXRfc2Vjb25kcyI6IDE1LCAic3RhcnRlZF9hdF91dGMiOiBzdGFydGVkfQogICAgdHJ5OgogICAgICAgIHJlc3VsdCA9IHN1YnByb2Nlc3MucnVuKGFyZ3YsIHN0ZG91dD1zdWJwcm9jZXNzLlBJUEUsIHN0ZGVycj1zdWJwcm9jZXNzLlBJUEUsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGltZW91dD0xNSwgY2hlY2s9RmFsc2UpCiAgICAgICAgcmVjb3JkWyJyZXR1cm5jb2RlIl0gPSByZXN1bHQucmV0dXJuY29kZQogICAgICAgIHJlY29yZFsic3Rkb3V0Il0gPSBieXRlc19yZWNvcmQocmVzdWx0LnN0ZG91dCkKICAgICAgICByZWNvcmRbInN0ZGVyciJdID0gYnl0ZXNfcmVjb3JkKHJlc3VsdC5zdGRlcnIpCiAgICAgICAgaWYgbGVuKHJlc3VsdC5zdGRvdXQpID4gTUFYX1NURE9VVCBvciBsZW4ocmVzdWx0LnN0ZGVycikgPiBNQVhfU1RERVJSOgogICAgICAgICAgICByZWNvcmRbImNvbGxlY3Rpb25fZXJyb3IiXSA9ICJvdXRwdXRfZXhjZWVkc19ib3VuZCIKICAgIGV4Y2VwdCBzdWJwcm9jZXNzLlRpbWVvdXRFeHBpcmVkIGFzIGV4YzoKICAgICAgICBzdGRvdXQgPSBleGMuc3Rkb3V0IG9yIGIiIgogICAgICAgIHN0ZGVyciA9IGV4Yy5zdGRlcnIgb3IgYiIiCiAgICAgICAgaWYgaXNpbnN0YW5jZShzdGRvdXQsIHN0cik6CiAgICAgICAgICAgIHN0ZG91dCA9IHN0ZG91dC5lbmNvZGUoInV0Zi04IikKICAgICAgICBpZiBpc2luc3RhbmNlKHN0ZGVyciwgc3RyKToKICAgICAgICAgICAgc3RkZXJyID0gc3RkZXJyLmVuY29kZSgidXRmLTgiKQogICAgICAgIHJlY29yZC51cGRhdGUoY29sbGVjdGlvbl9lcnJvcl90eXBlPXR5cGUoZXhjKS5fX25hbWVfXywgY29sbGVjdGlvbl9lcnJvcj0iY29tbWFuZF90aW1lZF9vdXQiLAogICAgICAgICAgICAgICAgICAgICAgcGFydGlhbF9zdGRvdXQ9Ynl0ZXNfcmVjb3JkKHN0ZG91dCksIHBhcnRpYWxfc3RkZXJyPWJ5dGVzX3JlY29yZChzdGRlcnIpKQogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBleGM6CiAgICAgICAgcmVjb3JkLnVwZGF0ZShjb2xsZWN0aW9uX2Vycm9yX3R5cGU9dHlwZShleGMpLl9fbmFtZV9fLCBjb2xsZWN0aW9uX2Vycm9yPXN0cihleGMpKQogICAgcmVjb3JkWyJmaW5pc2hlZF9hdF91dGMiXSA9IGRhdGV0aW1lLmRhdGV0aW1lLm5vdyhkYXRldGltZS50aW1lem9uZS51dGMpLmlzb2Zvcm1hdCgpCiAgICBlbWl0KHJlY29yZCkKCgpkZWYgcmVhZF9maWxlKGxhYmVsLCBwYXRoLCBsaW1pdD0yNjIxNDQpOgogICAgcmVjb3JkID0geyJzdGFnZSI6IGxhYmVsLCAicGF0aCI6IHN0cihwYXRoKX0KICAgIHRyeToKICAgICAgICB3aXRoIHBhdGgub3BlbigicmIiKSBhcyBzdHJlYW06CiAgICAgICAgICAgIGRhdGEgPSBzdHJlYW0ucmVhZChsaW1pdCArIDEpCiAgICAgICAgcmVjb3JkWyJjb250ZW50Il0gPSBieXRlc19yZWNvcmQoZGF0YSkKICAgICAgICBpZiBsZW4oZGF0YSkgPiBsaW1pdDoKICAgICAgICAgICAgcmVjb3JkWyJjb2xsZWN0aW9uX2Vycm9yIl0gPSAiZmlsZV9leGNlZWRzX2JvdW5kX2NvbnRlbnRfaXNfdHJ1bmNhdGVkX2FuZF91bmtub3duIgogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBleGM6CiAgICAgICAgcmVjb3JkLnVwZGF0ZShjb2xsZWN0aW9uX2Vycm9yX3R5cGU9dHlwZShleGMpLl9fbmFtZV9fLCBjb2xsZWN0aW9uX2Vycm9yPXN0cihleGMpKQogICAgZW1pdChyZWNvcmQpCiAgICByZXR1cm4gcmVjb3JkCgoKZGVmIGRlY29kZV9yZWNvcmQocmVjb3JkKToKICAgIHRyeToKICAgICAgICByZXR1cm4gYmFzZTY0LmI2NGRlY29kZShyZWNvcmRbImNvbnRlbnQiXVsiYmFzZTY0Il0pLmRlY29kZSgidXRmLTgiKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICByZXR1cm4gIiIKCgpkZWYgd2l0aGluKHBhdGgsIG1vdW50cG9pbnQpOgogICAgdHJ5OgogICAgICAgIHJldHVybiBvcy5wYXRoLmNvbW1vbnBhdGgoKHN0cihwYXRoKSwgc3RyKG1vdW50cG9pbnQpKSkgPT0gc3RyKG1vdW50cG9pbnQpCiAgICBleGNlcHQgKE9TRXJyb3IsIFZhbHVlRXJyb3IpOgogICAgICAgIHJldHVybiBGYWxzZQoKCmRlZiBjZ3JvdXBfZmlsZXMoY2dyb3VwX3RleHQsIG1vdW50aW5mb190ZXh0KToKICAgIG1lbWJlcnNoaXBzID0gW10KICAgIGZvciBsaW5lIGluIGNncm91cF90ZXh0LnNwbGl0bGluZXMoKToKICAgICAgICBwYXJ0cyA9IGxpbmUuc3BsaXQoIjoiLCAyKQogICAgICAgIGlmIGxlbihwYXJ0cykgPT0gMyBhbmQgcGFydHNbMl0uc3RhcnRzd2l0aCgiLyIpOgogICAgICAgICAgICBtZW1iZXJzaGlwcy5hcHBlbmQoKHNldChmaWx0ZXIoTm9uZSwgcGFydHNbMV0uc3BsaXQoIiwiKSkpLCBwYXJ0c1syXSkpCiAgICBtb3VudHMgPSBbXQogICAgZm9yIGxpbmUgaW4gbW91bnRpbmZvX3RleHQuc3BsaXRsaW5lcygpOgogICAgICAgIGxlZnQsIHNlcGFyYXRvciwgcmlnaHQgPSBsaW5lLnBhcnRpdGlvbigiIC0gIikKICAgICAgICBmaWVsZHMgPSBsZWZ0LnNwbGl0KCkKICAgICAgICBhZnRlciA9IHJpZ2h0LnNwbGl0KCkKICAgICAgICBpZiBzZXBhcmF0b3IgYW5kIGxlbihmaWVsZHMpID49IDYgYW5kIGxlbihhZnRlcikgPj0gMyBhbmQgYWZ0ZXJbMF0gaW4gKCJjZ3JvdXAiLCAiY2dyb3VwMiIpOgogICAgICAgICAgICBtb3VudHMuYXBwZW5kKChhZnRlclswXSwgcGF0aGxpYi5QYXRoKGZpZWxkc1szXSksIHBhdGhsaWIuUGF0aChmaWVsZHNbNF0pLCBzZXQoYWZ0ZXJbMl0uc3BsaXQoIiwiKSkpKQogICAgZm91bmQgPSBbXQogICAgZm9yIGZpbGVzeXN0ZW0sIHJvb3QsIG1vdW50cG9pbnQsIG9wdGlvbnMgaW4gbW91bnRzOgogICAgICAgIGZvciBjb250cm9sbGVycywgbWVtYmVyIGluIG1lbWJlcnNoaXBzOgogICAgICAgICAgICByZWxldmFudCA9IGNvbnRyb2xsZXJzICYgeyJkZXZpY2VzIiwgImNwdXNldCJ9CiAgICAgICAgICAgIG1vdW50X2NvbnRyb2xsZXJzID0gb3B0aW9ucyAmIHsiZGV2aWNlcyIsICJjcHVzZXQifQogICAgICAgICAgICBpZiAoZmlsZXN5c3RlbSA9PSAiY2dyb3VwMiIgYW5kIG5vdCBjb250cm9sbGVycykgb3IgKGZpbGVzeXN0ZW0gPT0gImNncm91cCIgYW5kIHJlbGV2YW50IGFuZCByZWxldmFudCA8PSBtb3VudF9jb250cm9sbGVycyk6CiAgICAgICAgICAgICAgICBtZW1iZXJfcGF0aCA9IHBhdGhsaWIuUHVyZVBvc2l4UGF0aChtZW1iZXIpCiAgICAgICAgICAgICAgICByb290X3BhdGggPSBwYXRobGliLlB1cmVQb3NpeFBhdGgocm9vdCkKICAgICAgICAgICAgICAgIHRyeToKICAgICAgICAgICAgICAgICAgICByZWxhdGl2ZSA9IG1lbWJlcl9wYXRoLnJlbGF0aXZlX3RvKHJvb3RfcGF0aCkKICAgICAgICAgICAgICAgIGV4Y2VwdCBWYWx1ZUVycm9yOgogICAgICAgICAgICAgICAgICAgIGZvdW5kLmFwcGVuZCh7ImZpbGVzeXN0ZW0iOiBmaWxlc3lzdGVtLCAiZXJyb3IiOiAibWVtYmVyc2hpcF9vdXRzaWRlX21vdW50X3Jvb3QifSkKICAgICAgICAgICAgICAgICAgICBjb250aW51ZQogICAgICAgICAgICAgICAgcmVzb2x2ZWRfbW91bnQgPSBtb3VudHBvaW50LnJlc29sdmUoc3RyaWN0PUZhbHNlKQogICAgICAgICAgICAgICAgY2FuZGlkYXRlID0gKHJlc29sdmVkX21vdW50IC8gcGF0aGxpYi5QYXRoKCpyZWxhdGl2ZS5wYXJ0cykpLnJlc29sdmUoc3RyaWN0PUZhbHNlKQogICAgICAgICAgICAgICAgaXRlbSA9IHsiZmlsZXN5c3RlbSI6IGZpbGVzeXN0ZW0sICJjb250cm9sbGVycyI6IHNvcnRlZChjb250cm9sbGVycyksCiAgICAgICAgICAgICAgICAgICAgICAgICJtb3VudHBvaW50Ijogc3RyKHJlc29sdmVkX21vdW50KSwgImNhbmRpZGF0ZSI6IHN0cihjYW5kaWRhdGUpfQogICAgICAgICAgICAgICAgaWYgbm90IHdpdGhpbihjYW5kaWRhdGUsIHJlc29sdmVkX21vdW50KToKICAgICAgICAgICAgICAgICAgICBpdGVtWyJlcnJvciJdID0gInJlc29sdmVkX3BhdGhfb3V0c2lkZV9tb3VudHBvaW50IgogICAgICAgICAgICAgICAgICAgIGZvdW5kLmFwcGVuZChpdGVtKQogICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgICAgICBpdGVtWyJmaWxlcyJdID0gW10KICAgICAgICAgICAgICAgIG5hbWVzID0gKCJjZ3JvdXAuY29udHJvbGxlcnMiLCAiY3B1c2V0LmNwdXMiLCAiY3B1c2V0LmNwdXMuZWZmZWN0aXZlIikgaWYgZmlsZXN5c3RlbSA9PSAiY2dyb3VwMiIgZWxzZSAoImRldmljZXMubGlzdCIsICJjcHVzZXQuY3B1cyIsICJjcHVzZXQuZWZmZWN0aXZlX2NwdXMiKQogICAgICAgICAgICAgICAgZm9yIG5hbWUgaW4gbmFtZXM6CiAgICAgICAgICAgICAgICAgICAgcGF0aCA9IGNhbmRpZGF0ZSAvIG5hbWUKICAgICAgICAgICAgICAgICAgICByZWMgPSB7Im5hbWUiOiBuYW1lLCAicGF0aCI6IHN0cihwYXRoKX0KICAgICAgICAgICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICAgICAgICAgIGRhdGEgPSBwYXRoLnJlYWRfYnl0ZXMoKQogICAgICAgICAgICAgICAgICAgICAgICByZWNbImNvbnRlbnQiXSA9IGJ5dGVzX3JlY29yZChkYXRhKQogICAgICAgICAgICAgICAgICAgICAgICBpZiBsZW4oZGF0YSkgPiA2NTUzNjoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIHJlY1siY29sbGVjdGlvbl9lcnJvciJdID0gImZpbGVfZXhjZWVkc19ib3VuZCIKICAgICAgICAgICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgICAgICAgICAgICAgcmVjLnVwZGF0ZShjb2xsZWN0aW9uX2Vycm9yX3R5cGU9dHlwZShleGMpLl9fbmFtZV9fLCBjb2xsZWN0aW9uX2Vycm9yPXN0cihleGMpKQogICAgICAgICAgICAgICAgICAgIGl0ZW1bImZpbGVzIl0uYXBwZW5kKHJlYykKICAgICAgICAgICAgICAgIGZvdW5kLmFwcGVuZChpdGVtKQogICAgZW1pdCh7InN0YWdlIjogIlNFTEZfQ0dST1VQX1JFU09MVVRJT04iLCAibWVtYmVyc2hpcHMiOiBsZW4obWVtYmVyc2hpcHMpLAogICAgICAgICAgIm1vdW50cyI6IGxlbihtb3VudHMpLCAicmVzb2x2ZWQiOiBmb3VuZH0pCgoKZGVmIG1haW4oKToKICAgIGVtaXQoeyJzdGFnZSI6ICJQUk9CRV9TVEFSVCIsICJvYnNlcnZlZF9hdF91dGMiOiBkYXRldGltZS5kYXRldGltZS5ub3coZGF0ZXRpbWUudGltZXpvbmUudXRjKS5pc29mb3JtYXQoKSwKICAgICAgICAgICJlbnZpcm9ubWVudCI6IHtuYW1lOiBvcy5lbnZpcm9uLmdldChuYW1lKSBmb3IgbmFtZSBpbiBFTlZfQUxMT1dMSVNUfSwKICAgICAgICAgICJlbnZpcm9ubWVudF9zY29wZSI6ICJhbGxvd2xpc3Rfb25seSIsICJleHBsaWNpdF9jdWRhX2FwaV9vcl9udW1lcmljX2NhbGxzIjogRmFsc2UsCiAgICAgICAgICAibnZpZGlhX3NtaV9tYXlfdXNlX2RyaXZlcl9pbnRlcm5hbGx5IjogVHJ1ZX0pCiAgICBjZ3JvdXAgPSByZWFkX2ZpbGUoIlBST0NfU0VMRl9DR1JPVVAiLCBwYXRobGliLlBhdGgoIi9wcm9jL3NlbGYvY2dyb3VwIikpCiAgICByZWFkX2ZpbGUoIlBST0NfU0VMRl9TVEFUVVMiLCBwYXRobGliLlBhdGgoIi9wcm9jL3NlbGYvc3RhdHVzIikpCiAgICBtb3VudGluZm8gPSByZWFkX2ZpbGUoIlBST0NfU0VMRl9NT1VOVElORk8iLCBwYXRobGliLlBhdGgoIi9wcm9jL3NlbGYvbW91bnRpbmZvIikpCiAgICBjZ3JvdXBfZmlsZXMoZGVjb2RlX3JlY29yZChjZ3JvdXApLCBkZWNvZGVfcmVjb3JkKG1vdW50aW5mbykpCiAgICB0cnk6CiAgICAgICAgYWZmaW5pdHkgPSBvcy5zY2hlZF9nZXRhZmZpbml0eSgwKQogICAgICAgIGVtaXQoeyJzdGFnZSI6ICJTQ0hFRFVMRVJfQUZGSU5JVFkiLCAiY3B1X2lkcyI6IHNvcnRlZChhZmZpbml0eSksICJvYnNlcnZlZF9jcHVfY291bnQiOiBsZW4oYWZmaW5pdHkpfSkKICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXhjOgogICAgICAgIGVtaXQoeyJzdGFnZSI6ICJTQ0hFRFVMRVJfQUZGSU5JVFkiLCAiY29sbGVjdGlvbl9lcnJvcl90eXBlIjogdHlwZShleGMpLl9fbmFtZV9fLCAiY29sbGVjdGlvbl9lcnJvciI6IHN0cihleGMpfSkKICAgIG1lbWluZm8gPSByZWFkX2ZpbGUoIlBST0NfTUVNSU5GTyIsIHBhdGhsaWIuUGF0aCgiL3Byb2MvbWVtaW5mbyIpKQogICAgbWVtX2F2YWlsYWJsZSA9IE5vbmUKICAgIGlmICJjb2xsZWN0aW9uX2Vycm9yIiBub3QgaW4gbWVtaW5mbzoKICAgICAgICBmb3IgbGluZSBpbiBkZWNvZGVfcmVjb3JkKG1lbWluZm8pLnNwbGl0bGluZXMoKToKICAgICAgICAgICAgaWYgbGluZS5zdGFydHN3aXRoKCJNZW1BdmFpbGFibGU6Iik6CiAgICAgICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICAgICAgbWVtX2F2YWlsYWJsZSA9IGludChsaW5lLnNwbGl0KClbMV0pICogMTAyNAogICAgICAgICAgICAgICAgZXhjZXB0IChJbmRleEVycm9yLCBWYWx1ZUVycm9yKToKICAgICAgICAgICAgICAgICAgICBwYXNzCiAgICBlbWl0KHsic3RhZ2UiOiAiTUVNT1JZX0FWQUlMQUJMRSIsICJtZW1fYXZhaWxhYmxlX2J5dGVzIjogbWVtX2F2YWlsYWJsZSwKICAgICAgICAgICJ1bmtub3duIjogbWVtX2F2YWlsYWJsZSBpcyBOb25lfSkKICAgIGRldmljZXMgPSBbXQogICAgZm9yIGluZGV4IGluIHJhbmdlKDgpOgogICAgICAgIHBhdGggPSBwYXRobGliLlBhdGgoZiIvZGV2L252aWRpYXtpbmRleH0iKQogICAgICAgIGl0ZW0gPSB7InBhdGgiOiBzdHIocGF0aCksICJvcGVuZWQiOiBGYWxzZX0KICAgICAgICB0cnk6CiAgICAgICAgICAgIGluZm8gPSBwYXRoLnN0YXQoKQogICAgICAgICAgICBpdGVtLnVwZGF0ZShtb2RlPXN0YXQuZmlsZW1vZGUoaW5mby5zdF9tb2RlKSwgaXNfY2hhcmFjdGVyX2RldmljZT1zdGF0LlNfSVNDSFIoaW5mby5zdF9tb2RlKSwKICAgICAgICAgICAgICAgICAgICAgICAgbWFqb3I9b3MubWFqb3IoaW5mby5zdF9yZGV2KSwgbWlub3I9b3MubWlub3IoaW5mby5zdF9yZGV2KSkKICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4YzoKICAgICAgICAgICAgaXRlbS51cGRhdGUoY29sbGVjdGlvbl9lcnJvcl90eXBlPXR5cGUoZXhjKS5fX25hbWVfXywgY29sbGVjdGlvbl9lcnJvcj1zdHIoZXhjKSkKICAgICAgICBkZXZpY2VzLmFwcGVuZChpdGVtKQogICAgZW1pdCh7InN0YWdlIjogIk5WSURJQV9ERVZJQ0VfU1RBVF9PTkxZIiwgImRldmljZXMiOiBkZXZpY2VzfSkKICAgIGNvbW1hbmQoIkdQVV9JTlZFTlRPUlkiLCBbIm52aWRpYS1zbWkiLCAiLS1xdWVyeS1ncHU9aW5kZXgsbWlub3JfbnVtYmVyLHV1aWQsbmFtZSxwY2kuYnVzX2lkLG1lbW9yeS50b3RhbCxtZW1vcnkuZnJlZSxtZW1vcnkudXNlZCx1dGlsaXphdGlvbi5ncHUiLCAiLS1mb3JtYXQ9Y3N2LG5vaGVhZGVyLG5vdW5pdHMiXSkKICAgIGNvbW1hbmQoIkNPTVBVVEVfQVBQTElDQVRJT05TIiwgWyJudmlkaWEtc21pIiwgIi0tcXVlcnktY29tcHV0ZS1hcHBzPWdwdV91dWlkLHBpZCx1c2VkX2dwdV9tZW1vcnkiLCAiLS1mb3JtYXQ9Y3N2LG5vaGVhZGVyLG5vdW5pdHMiXSkKICAgIGNvbW1hbmQoIlBNT05fUkFXX1VOUEFSU0VEIiwgWyJudmlkaWEtc21pIiwgInBtb24iLCAiLWMiLCAiMSJdKQogICAgam9iX2lkID0gb3MuZW52aXJvbi5nZXQoIlNMVVJNX0pPQl9JRCIpCiAgICBpZiBqb2JfaWQ6CiAgICAgICAgY29tbWFuZCgiQUxMT0NBVEVEX0pPQl9ERVRBSUwiLCBbInNjb250cm9sIiwgIi1kIiwgInNob3ciLCAiam9iIiwgam9iX2lkXSkKICAgIGVsc2U6CiAgICAgICAgZW1pdCh7InN0YWdlIjogIkFMTE9DQVRFRF9KT0JfREVUQUlMIiwgImNvbGxlY3Rpb25fZXJyb3IiOiAiU0xVUk1fSk9CX0lEX21pc3NpbmcifSkKICAgIGVtaXQoeyJzdGF0dXMiOiAiU0lOR0xFX0dQVV9SRVNPVVJDRV9ESUFHTk9TVElDX1NOQVBTSE9UX09OTFkiLCAic2NvcGUiOiAidGhpc19hbGxvY2F0aW9uX2FuZF9zbmFwc2hvdF90aW1lX29ubHkiLAogICAgICAgICAgImFic2VuY2Vfb2ZfY3VkYV92aXNpYmxlX2RldmljZXNfbWVhbnNfaXNvbGF0aW9uX3VudmVyaWZpZWQiOiBub3QgYm9vbChvcy5lbnZpcm9uLmdldCgiQ1VEQV9WSVNJQkxFX0RFVklDRVMiKSksCiAgICAgICAgICAidHJhaW5pbmdfc3RhcnRlZCI6IEZhbHNlLCAidG9yY2hfaW1wb3J0ZWQiOiBGYWxzZSwgImV4cGxpY2l0X2N1ZGFfbnVtZXJpY19jb21wdXRlIjogRmFsc2UsCiAgICAgICAgICAibnZpZGlhX3NtaV9pbnRlcm5hbF9kcml2ZXJfYmVoYXZpb3Jfbm90X2NsYWltZWQiOiBUcnVlfSkKCgppZiBfX25hbWVfXyA9PSAiX19tYWluX18iOgogICAgbWFpbigpCg==')
slurm_bytes=base64.b64decode('IyEvdXNyL2Jpbi9lbnYgYmFzaAojU0JBVENIIC0tam9iLW5hbWU9a2RwcC1zaW5nbGUtZ3B1LWRpYWdub3N0aWMtNDkKI1NCQVRDSCAtLXBhcnRpdGlvbj1oZ3B1OAojU0JBVENIIC0tbm9kZWxpc3Q9bmd1MjAxCiNTQkFUQ0ggLS1ub2Rlcz0xCiNTQkFUQ0ggLS1udGFza3M9MQojU0JBVENIIC0tY3B1cy1wZXItdGFzaz0xCiNTQkFUQ0ggLS1ncmVzPWdwdToxCiNTQkFUQ0ggLS10aW1lPTAwOjAyOjAwCiNTQkFUQ0ggLS1kZWFkbGluZT1ub3crMTBtaW51dGVzCiNTQkFUQ0ggLS1uby1yZXF1ZXVlCiNTQkFUQ0ggLS1jaGRpcj0vZGF0YTEvaG9tZS9zdW55aXEva2FsbWFubmV0X2RhaWx5X2NhbWVsc19wZXJfYmFzaW5fcGlsb3RzXzIwMjYwOTAxL2dwdV9zaGFyaW5nX2RpYWdub3N0aWNfMjAyNjA5MDcvcmVxdWVzdDQ5CiNTQkFUQ0ggLS1vdXRwdXQ9L2RhdGExL2hvbWUvc3VueWlxL2thbG1hbm5ldF9kYWlseV9jYW1lbHNfcGVyX2Jhc2luX3BpbG90c18yMDI2MDkwMS9ncHVfc2hhcmluZ19kaWFnbm9zdGljXzIwMjYwOTA3L3JlcXVlc3Q0OS9zbHVybS0lai5zdGRvdXQKI1NCQVRDSCAtLWVycm9yPS9kYXRhMS9ob21lL3N1bnlpcS9rYWxtYW5uZXRfZGFpbHlfY2FtZWxzX3Blcl9iYXNpbl9waWxvdHNfMjAyNjA5MDEvZ3B1X3NoYXJpbmdfZGlhZ25vc3RpY18yMDI2MDkwNy9yZXF1ZXN0NDkvc2x1cm0tJWouc3RkZXJyCnNldCAtZW8gcGlwZWZhaWwKdW1hc2sgMDc3CltbICIke1NMVVJNX1JFU1RBUlRfQ09VTlQ6LTB9IiA9PSAwIF1dIHx8IGV4aXQgODIKW1sgLW4gIiR7U0xVUk1fSk9CX0lEOi19IiAmJiAiJChob3N0bmFtZSAtcykiID09IG5ndTIwMSBdXSB8fCBleGl0IDgxCmV4cG9ydCBQWVRIT05ET05UV1JJVEVCWVRFQ09ERT0xIFBZVEhPTk9QVElNSVpFPTAKZXhwb3J0IE9NUF9OVU1fVEhSRUFEUz0xIE1LTF9OVU1fVEhSRUFEUz0xIE9QRU5CTEFTX05VTV9USFJFQURTPTEgTlVNRVhQUl9OVU1fVEhSRUFEUz0xCmV4ZWMgL2RhdGExL2hvbWUvc3VueWlxL21pbmljb25kYTMvZW52cy9uaF9maW5hbC9iaW4vcHl0aG9uIC1JIC1CIC9kYXRhMS9ob21lL3N1bnlpcS9rYWxtYW5uZXRfZGFpbHlfY2FtZWxzX3Blcl9iYXNpbl9waWxvdHNfMjAyNjA5MDEvZ3B1X3NoYXJpbmdfZGlhZ25vc3RpY18yMDI2MDkwNy9yZXF1ZXN0NDkvcHJvYmUucHkK')
require(len(probe_bytes)==8968 and sha(probe_bytes)=='d409aa71dd2c4b8977aa6c75016edd59fdd0061466f979bf6caf68785bf973f6','embedded probe mismatch')
require(len(slurm_bytes)==1164 and sha(slurm_bytes)=='5ccedf847b4931f5b7e44bac4d2f720f9a69e1eb1ac49aa7e77e1c1bc6305020','embedded Slurm mismatch')
def captured(label,args,timeout=30,limit=262144):
    started_at=datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout,check=False)
        record={'stage':label,'argv':args,'returncode':result.returncode,
                'stdout_base64':base64.b64encode(result.stdout).decode(),'stdout_bytes':len(result.stdout),'stdout_sha256':sha(result.stdout),
                'stderr_base64':base64.b64encode(result.stderr).decode(),'stderr_bytes':len(result.stderr),'stderr_sha256':sha(result.stderr)}
        if len(result.stdout)>limit or len(result.stderr)>65536: record['collection_error']='output_exceeds_expected_bound_full_bytes_retained'
    except subprocess.TimeoutExpired as exc:
        stdout=exc.stdout or b'';stderr=exc.stderr or b''
        if isinstance(stdout,str):stdout=stdout.encode()
        if isinstance(stderr,str):stderr=stderr.encode()
        record={'stage':label,'argv':args,'query_error_type':type(exc).__name__,'query_error':'command_timed_out',
                'partial_stdout_base64':base64.b64encode(stdout).decode(),'partial_stdout_bytes':len(stdout),'partial_stdout_sha256':sha(stdout),
                'partial_stderr_base64':base64.b64encode(stderr).decode(),'partial_stderr_bytes':len(stderr),'partial_stderr_sha256':sha(stderr)}
    except Exception as exc:
        record={'stage':label,'argv':args,'query_error_type':type(exc).__name__,'query_error':str(exc)}
    record['started_at_utc']=started_at
    record['finished_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(json.dumps(record,sort_keys=True),flush=True)
    return record
def successful(record):
    return record.get('returncode')==0 and 'query_error' not in record and 'collection_error' not in record
def stdout_text(record):
    return base64.b64decode(record['stdout_base64']).decode('utf-8')
help_record=captured('SBATCH_HELP',['sbatch','--help'])
require(successful(help_record) and '--deadline' in stdout_text(help_record),'sbatch --deadline support not confirmed before writes')
target=root/'gpu_sharing_diagnostic_20260907/request49'
parent=target.parent
require(parent.parent==root and root.resolve()==root and not root.is_symlink(),'diagnostic parent anchor differs')
require(not parent.exists() or (parent.is_dir() and parent.resolve()==parent and not parent.is_symlink()),'diagnostic parent differs')
require(not target.exists() and not target.is_symlink(),'request49 already exists; do not resubmit')
node=captured('NODE_NGU201',['scontrol','-d','show','node','ngu201'])
partition=captured('PARTITION_HGPU8',['scontrol','show','partition','hgpu8'])
reservations=captured('CURRENT_RESERVATIONS',['scontrol','-o','show','reservation'])
queue=captured('OWN_QUEUE_FOR_RELATED_JOB_SCREEN',['squeue','-h','-u',str(os.getuid()),'-o','%i|%j|%T|%N|%C|%b'])
require(all(successful(item) for item in (node,partition,reservations,queue)),'preflight query failed')
node_text=stdout_text(node); partition_text=stdout_text(partition); reservation_text=stdout_text(reservations); queue_text=stdout_text(queue)
require(re.search(r'\bNodeName=ngu201\b',node_text),'ngu201 detail missing')
cpu_total=re.search(r'\bCPUTot=(\d+)',node_text); cpu_alloc=re.search(r'\bCPUAlloc=(\d+)',node_text)
require(cpu_total and cpu_alloc and int(cpu_total.group(1))-int(cpu_alloc.group(1))>=1,'fewer than one unallocated CPU')
gpu_cfg=re.search(r'\bGres=gpu:(\d+)(?:\([^\n]*\))?',node_text); gpu_alloc=re.search(r'\bGresUsed=gpu:(\d+)(?:\([^\n]*\))?',node_text)
require(gpu_cfg and gpu_alloc and int(gpu_cfg.group(1))-int(gpu_alloc.group(1))>=1,'GPU configured/used counts missing or fewer than one unallocated GPU')
state_match=re.search(r'\bState=([^ \n]+)',node_text)
require(state_match and state_match.group(1).split('+',1)[0] in {'IDLE','ALLOCATED','MIXED'},'node state is not schedulable')
require(not re.search(r'(DOWN|DRAIN|MAINT|RESERVED|FAIL|NO_RESPOND|POWERING_DOWN)',state_match.group(1),re.I),'node has an unschedulable state flag')
require(re.search(r'\bPartitionName=hgpu8\b',partition_text),'hgpu8 detail missing')
require(re.search(r'\bPreemptMode=OFF\b',partition_text),'partition preemption is not OFF')
require(re.search(r'\bState=UP\b',partition_text),'partition is not UP')
related_lines=[line for line in queue_text.splitlines() if re.search(r'(?i)(kdpp|kalmannet[-_]?daily[-_]?per[-_]?basin)',line.split('|',2)[1] if '|' in line else '')]
require(not related_lines,'related per-basin task job already exists')
reservation_expansions=[]
for line in reservation_text.splitlines():
    match=re.search(r'\bNodes=([^ ]+)',line)
    if not match or match.group(1) in {'(null)','None'} or re.search(r'\bState=INACTIVE\b',line): continue
    expansion=captured('RESERVATION_HOSTNAMES',['scontrol','show','hostnames',match.group(1)])
    require(successful(expansion),'reservation host expansion failed')
    reservation_expansions.append(expansion)
    require('ngu201' not in stdout_text(expansion).split(),'active reservation includes ngu201')
require(not target.exists() and not target.is_symlink(),'request49 appeared during preflight; do not resubmit')
if not parent.exists(): os.mkdir(parent,0o700)
require(parent.is_dir() and parent.resolve()==parent and not parent.is_symlink(),'diagnostic parent creation differs')
os.mkdir(target,0o700)
require(target.resolve()==target and not target.is_symlink(),'created target differs')
def exclusive(path,data,mode=0o600):
    descriptor=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,mode)
    with os.fdopen(descriptor,'wb') as stream:
        stream.write(data);stream.flush();os.fsync(stream.fileno())
    require(path.read_bytes()==data and not path.is_symlink(),'exclusive write verification failed: '+path.name)
exclusive(target/'probe.py',probe_bytes)
exclusive(target/'probe.slurm',slurm_bytes,0o700)
submitted_at=datetime.datetime.now(datetime.timezone.utc).isoformat()
intent={'schema_version':'single_gpu_resource_diagnostic_submission_intent_v1','request_sequence':49,
        'node':'ngu201','partition':'hgpu8','nodes':1,'tasks':1,'requested_cpus_per_task':1,'requested_gpus':1,
        'time_limit':'00:02:00','relative_deadline':'now+10minutes','submitted_at_utc':submitted_at,
        'probe_sha256':sha(probe_bytes),'slurm_sha256':sha(slurm_bytes),'training':False,'sbatch_calls_allowed':1,
        'preflight':[node,partition,reservations,queue,help_record]+reservation_expansions}
intent_bytes=(json.dumps(intent,sort_keys=True,indent=2)+'\n').encode()
exclusive(target/'submission-intent.json',intent_bytes)
job_script=target/'probe.slurm'
submission_started=datetime.datetime.now(datetime.timezone.utc).isoformat()
try:
    sbatch_environment={key:value for key,value in os.environ.items() if not key.startswith('SBATCH_')}
    submission=subprocess.run(['sbatch', str(job_script)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=45,check=False,env=sbatch_environment)
    submission_stdout=submission.stdout;submission_stderr=submission.stderr;submission_returncode=submission.returncode;submission_error=None
except subprocess.TimeoutExpired as exc:
    submission_stdout=exc.stdout or b'';submission_stderr=exc.stderr or b''
    if isinstance(submission_stdout,str):submission_stdout=submission_stdout.encode()
    if isinstance(submission_stderr,str):submission_stderr=submission_stderr.encode()
    submission_returncode=None;submission_error='TimeoutExpired'
submission_finished=datetime.datetime.now(datetime.timezone.utc).isoformat()
submission_collection_error='output_exceeds_expected_bound_full_bytes_retained' if len(submission_stdout)>65536 or len(submission_stderr)>65536 else None
matches=re.findall(rb'(?m)^Submitted batch job ([0-9]+)\s*$',submission_stdout)
job_id=matches[0].decode() if submission_returncode==0 and submission_collection_error is None and len(matches)==1 else None
deadline_record=captured('SUBMITTED_JOB_DETAIL',['scontrol','-d','show','job',job_id]) if job_id else {'stage':'SUBMITTED_JOB_DETAIL','not_run':'ambiguous_submission'}
deadline_text=stdout_text(deadline_record) if successful(deadline_record) else ''
deadline_match=re.search(r'\bDeadline=([^ ]+)',deadline_text)
receipt={'schema_version':'single_gpu_resource_diagnostic_submission_receipt_v1','request_sequence':49,
         'submission_returncode':submission_returncode,'submission_error':submission_error,
         'submission_collection_error':submission_collection_error,
         'submission_stdout_base64':base64.b64encode(submission_stdout).decode(),
         'submission_stdout_bytes':len(submission_stdout),'submission_stdout_sha256':sha(submission_stdout),
         'submission_stderr_base64':base64.b64encode(submission_stderr).decode(),'submission_stderr_bytes':len(submission_stderr),
         'submission_stderr_sha256':sha(submission_stderr),'job_id':job_id,'submitted_at_utc':submitted_at,
         'submission_started_at_utc':submission_started,'submission_finished_at_utc':submission_finished,
         'relative_deadline':'now+10minutes','scheduler_deadline':deadline_match.group(1) if deadline_match else None,
         'job_detail':deadline_record,'sbatch_calls':1,'automatic_retry':False,'training_submissions':0}
exclusive(target/'submission-receipt.json',(json.dumps(receipt,sort_keys=True,indent=2)+'\n').encode())
require(job_id is not None,'ambiguous or failed submission; evidence retained; no automatic retry')
require(successful(deadline_record) and deadline_match,'scheduler Deadline not confirmed in receipt')
print(json.dumps({'status':'SINGLE_GPU_RESOURCE_DIAGNOSTIC_SUBMITTED_NOT_COMPLETED','request_sequence':49,
                  'job_id':job_id,'node':'ngu201','requested_cpus_per_task':1,'requested_gpus':1,
                  'actual_allocation_must_be_observed_in_job':True,'training_submissions':0,'sbatch_calls':1,
                  'automatic_retry':False,'target':str(target)},sort_keys=True),flush=True)
PY_SUBMIT
