#!/usr/bin/env bash
# Read-only prerequisites for the user-approved complete model-selection study.
set -euo pipefail
test -x /data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python
python3 - <<'PY'
import base64, gzip, hashlib, json, os, pathlib, subprocess
base = pathlib.Path('/data1/home/sunyiq')
new = base / 'kalmannet_wrr_model_selection_20260908'
assert not os.path.lexists(new), 'New study root already exists; inspect, do not overwrite'
exp_rel = pathlib.Path('experiments/optimize_hyper_parameters/wrr_hp_extension_20260902')
roots = {'extension': base / 'kalmannet_wrr_hp_extension_20260902',
         'replication': base / 'kalmannet_wrr_finalist_replication_20260907'}
indices = {'extension': [0,1,2,3,4,6,7,8,9,10,11,12,13,14,15,16,18,19,20,21,22,23,24,25],
           'replication': list(range(6))}
protected = {}

def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()

def remember(path, expected=None):
    actual = sha(path)
    assert expected is None or actual == expected, (str(path), actual, expected)
    protected[str(path)] = actual
    return actual

def safe_source(repo, relative):
    pure = pathlib.PurePosixPath(relative)
    assert not pure.is_absolute() and '..' not in pure.parts and '\\' not in relative
    path = repo.joinpath(*pure.parts)
    assert path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(repo.resolve())
    return path

references, manifests = [], {}
for label, root in roots.items():
    repo, experiment = root / 'repo', root / 'repo' / exp_rel
    mp = experiment / 'source_manifest.json'
    manifest = json.loads(mp.read_bytes())
    manifests[label] = {'path': str(mp), 'sha256': remember(mp), 'source_count': len(manifest['source_sha256'])}
    for relative, expected in manifest['source_sha256'].items():
        remember(safe_source(repo, relative), expected)
    all_audits = [(ap, json.loads(ap.read_bytes())) for ap in experiment.glob('audits/*_formal_*.json')]
    for index in indices[label]:
        paths = list(experiment.glob('runs/formal_seed*_gpu/idx%04d_*/cell_metrics.json' % index))
        assert len(paths) == 1, (label, index, paths)
        cp = paths[0]
        cell = json.loads(cp.read_bytes())
        audits = [(p,a) for p,a in all_audits if a.get('run_id') == cell['run_id']]
        assert len(audits) == 1, (label,index,'audit count',len(audits))
        ap, audit = audits[0]
        assert audit['launcher_status'] == 'ok' and audit['held_out_test_loaded'] is False
        assert cell['seed'] == cell['combo']['seed'] == audit['runtime']['seed']
        checkpoint = cp.parent / 'results/best_model.pt'
        checkpoint_hash = remember(checkpoint, cell['validation_scoring']['best_checkpoint_sha256'])
        config = cp.parent / 'config_used.yaml'
        references.append({'family': label, 'index': index, 'run_id': cell['run_id'],
            'combo': cell['combo'], 'score': cell['validation_scoring']['pooled_mean_leads_1_12_corrected_def'],
            'cell_path': str(cp), 'cell_sha256': remember(cp),
            'checkpoint_path': str(checkpoint), 'checkpoint_sha256': checkpoint_hash,
            'config_path': str(config), 'config_sha256': remember(config),
            'audit_path': str(ap), 'audit_sha256': remember(ap), 'runtime': audit['runtime'],
            'train_seconds': cell['train_seconds']})
failed = []
experiment = roots['extension'] / 'repo' / exp_rel
for index, seed in [(5,42),(17,43)]:
    paths = list(experiment.glob('runs/formal_seed%d_gpu/idx%04d_*/error.txt' % (seed,index)))
    assert len(paths) == 1
    error = paths[0]
    assert 'Exceeded max NaN recoveries in this epoch' in error.read_text()
    assert (error.parent / 'FAILED').is_file()
    failed.append({'index':index,'seed':seed,'error_path':str(error),'error_sha256':remember(error),
                   'failed_marker_sha256':remember(error.parent / 'FAILED'),
                   'classification':'numeric_recovery_limit','retry_authorized':False})
data={}
for split,name,expected in [
    ('train','train_win800_19990101_01-20070527_03.pt','3a4f94a2562278f09b67853ac77e060766296007cb8f8a762756ffe792792440'),
    ('val','val_win800_20070527_04-20090314_13.pt','2e195fc974b5cc8cdb35df3cb7fd72a202af033ecc415acc03a87020b00bd403')]:
    path=roots['extension']/'repo/data/processed/high_flow_aug'/name
    data[split]={'path':str(path),'resolved_path':str(path.resolve()),'bytes':path.stat().st_size,'sha256':remember(path,expected)}
accounting=subprocess.check_output(['sacct','-j','223697','-X','-n','-P','--format=JobID,State,ExitCode'],text=True)
accounting_rows=[line.split('|')[:3] for line in accounting.splitlines() if line.strip()]
assert sorted(row[0] for row in accounting_rows)==['223697_'+str(i) for i in range(6)]
assert all(row[1:] == ['COMPLETED','0:0'] for row in accounting_rows)
environment=json.loads(subprocess.check_output([
    '/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python','-B','-c',
    'import importlib.metadata,json,platform; print(json.dumps(dict(python_version=platform.python_version(),torch_version=importlib.metadata.version("torch"),numpy_version=importlib.metadata.version("numpy"))))'
],text=True))
assert environment=={'python_version':'3.11.13','torch_version':'2.4.0','numpy_version':'2.3.3'}, environment
result={'probe':'PASS','new_family_root':str(new),'new_family_absent':True,
        'source_manifests':manifests,'references':references,'failed_runs':failed,'protected_files':protected,
        'data':data,'current_environment':environment,'prior_replication_accounting':accounting_rows,
        'data_tensors_loaded':False,'new_jobs_submitted':0}
blob=json.dumps(result,sort_keys=True,separators=(',',':')).encode()
print('REMOTE_BASELINE_GZIP_BASE64='+base64.b64encode(gzip.compress(blob,mtime=0)).decode())
print('PROBE_SUMMARY='+json.dumps({'probe':'PASS','references':len(references),'failed_runs':len(failed),
                                  'protected_files':len(protected),'data_splits':list(data),'new_jobs_submitted':0}))
PY
sinfo -p hgpu2p -N -h -o '%N|%t|%G'
