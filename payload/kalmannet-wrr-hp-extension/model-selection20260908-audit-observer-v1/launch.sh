#!/usr/bin/env bash
# Read-only audit collection. No certificate flag, scheduler writes, or tensor imports.
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-audit-observer-v1
cd "$PAYLOAD"
exec /data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B -I - "$PAYLOAD" <<'PY'
import hashlib
import json
import pathlib
import runpy
import sys

payload = pathlib.Path(sys.argv[1])
expected_payload = '/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-audit-observer-v1'
family = '/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908'
receipt = family + '/stages/A/SUBMISSION_RECEIPT.json'
if str(payload) != expected_payload or payload.resolve() != payload or payload.is_symlink():
    raise SystemExit('Unsafe observer payload root')
manifest_path = payload / 'OBSERVER_MANIFEST.json'
if manifest_path.is_symlink() or not manifest_path.is_file():
    raise SystemExit('Unsafe observer manifest')
manifest_bytes = manifest_path.read_bytes()
if hashlib.sha256(manifest_bytes).hexdigest() != '22d8bf89c3998ae6e2b94cd3e32780939872651dff40834e668d826298b9fa4a':
    raise SystemExit('Observer manifest hash mismatch')
manifest = json.loads(manifest_bytes)
if (manifest['kind'] != 'READ_ONLY_STAGE_A_AUDIT_TRANSPORT' or manifest['schema_version'] != 1
        or manifest['remote_payload'] != expected_payload or manifest['remote_family'] != family
        or manifest['stage'] != 'A' or manifest['receipt'] != receipt
        or manifest['certificate_write'] is not False or manifest['training_submission'] is not False):
    raise SystemExit('Observer manifest contract mismatch')
required = {'.gitattributes', 'audit_stage.py', 'build_package.py', 'deploy_remote.py',
            'launch_once.py', 'study_config.py', 'evidence_contract.py'}
if set(manifest['files']) != required:
    raise SystemExit('Observer manifest file inventory mismatch')
if {p.name for p in payload.iterdir()} != required | {'OBSERVER_MANIFEST.json', 'launch.sh'}:
    raise SystemExit('Unexpected observer transport entry')
for name, expected_hash in manifest['files'].items():
    path = payload / name
    if path.is_symlink() or not path.is_file() or path.resolve() != path:
        raise SystemExit('Unsafe observer source: ' + name)
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected_hash:
        raise SystemExit('Observer source hash mismatch: ' + name)
sys.path.insert(0, str(payload))
sys.argv = [str(payload / 'audit_stage.py'), '--family', family, '--stage', 'A', '--receipt', receipt]
runpy.run_path(str(payload / 'audit_stage.py'), run_name='__main__')
PY
