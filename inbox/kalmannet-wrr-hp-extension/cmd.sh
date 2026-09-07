#!/usr/bin/env bash
# Read-only remote prerequisites for the authorized six validation replicas.
set -euo pipefail
OLD_ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
NEW_ROOT=/data1/home/sunyiq/kalmannet_wrr_finalist_replication_20260907
test ! -e "$NEW_ROOT"
test ! -L "$NEW_ROOT"
test -x /data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python
python3 - "$OLD_ROOT" "$NEW_ROOT" <<'PY'
import glob, hashlib, json, os, pathlib, sys
old = pathlib.Path(sys.argv[1])
repo = old / 'repo'
exp = repo / 'experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()
manifest_path = exp / 'source_manifest.json'
manifest_sha = sha(manifest_path)
assert manifest_sha == 'f6f04298895e7a95e4a2fb88a160a98ba2b2c0fab1967cfa4ff6b8efc14904ad', manifest_sha
manifest = json.loads(manifest_path.read_text())
for rel, expected in manifest['source_sha256'].items():
    actual = sha(repo / rel)
    assert actual == expected, (rel, actual, expected)
references = []
for idx in [14, 12, 10, 9, 18, 19]:
    paths = list(exp.glob('runs/formal_seed*_gpu/idx%04d_*/cell_metrics.json' % idx))
    assert len(paths) == 1, (idx, paths)
    p = paths[0]
    cell = json.loads(p.read_text())
    checkpoint = p.parent / 'results/best_model.pt'
    ck_sha = sha(checkpoint)
    assert ck_sha == cell['validation_scoring']['best_checkpoint_sha256']
    audits = []
    for ap in exp.glob('audits/*_formal_*.json'):
        a = json.loads(ap.read_text())
        if a.get('run_id') == cell['run_id'] and a.get('launcher_status') == 'ok':
            audits.append({'path': str(ap), 'sha256': sha(ap), 'runtime': a['runtime']})
    assert len(audits) == 1, (idx, audits)
    references.append({'index': idx, 'cell_path': str(p), 'cell_sha256': sha(p),
      'checkpoint_sha256': ck_sha, 'combo': cell['combo'], 'audit': audits[0]})
data = {}
for split, name, expected in [
 ('train', 'train_win800_19990101_01-20070527_03.pt', '3a4f94a2562278f09b67853ac77e060766296007cb8f8a762756ffe792792440'),
 ('val', 'val_win800_20070527_04-20090314_13.pt', '2e195fc974b5cc8cdb35df3cb7fd72a202af033ecc415acc03a87020b00bd403')]:
    p = repo / 'data/processed/high_flow_aug' / name
    actual = sha(p)
    assert actual == expected, (split, actual)
    data[split] = {'path': str(p), 'resolved_path': str(p.resolve()), 'bytes': p.stat().st_size, 'sha256': actual}
print(json.dumps({'probe': 'PASS', 'old_manifest_sha256': manifest_sha, 'old_sources_verified': len(manifest['source_sha256']),
 'new_root': sys.argv[2], 'new_root_absent': True, 'references': references, 'data': data}, indent=2))
PY
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import importlib.metadata, json, platform
print(json.dumps({'current_environment': {'python': platform.python_version(),
 'torch_distribution': importlib.metadata.version('torch'), 'numpy_distribution': importlib.metadata.version('numpy')}}))
PY
sinfo -p hgpu2p -N -h -o '%N|%t|%G'
