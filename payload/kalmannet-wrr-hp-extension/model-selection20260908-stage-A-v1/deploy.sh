#!/usr/bin/env bash
# Invoked by the reviewed builder's manifest-pinned launch.sh. No retries.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Expected payload and frozen transport-manifest SHA256'; exit 1; }
PAYLOAD=$1
EXPECTED=$2
[[ "$EXPECTED" =~ ^[0-9a-f]{64}$ ]] || exit 1
cd "$PAYLOAD"
[[ ! -L TRANSPORT_MANIFEST.json && -f TRANSPORT_MANIFEST.json ]] || exit 1
printf '%s  TRANSPORT_MANIFEST.json\n' "$EXPECTED" | sha256sum -c -
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - "$PAYLOAD" <<'PY'
import hashlib, json, pathlib, re, sys
payload = pathlib.Path(sys.argv[1])
if not payload.is_absolute() or payload.resolve() != payload or '..' in payload.parts:
    raise SystemExit('Unsafe transport root')
manifest = json.loads((payload / 'TRANSPORT_MANIFEST.json').read_bytes())
root = '/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908'
mailbox = '/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension'
if manifest['schema_version'] != 1 or manifest['stage'] != 'A' or manifest['remote_family_root'] != root or manifest['remote_stage_root'] != root + '/stages/A' or manifest['dry_run'] is not False:
    raise SystemExit('Transport admission mismatch')
if str(payload.parent) != mailbox or not re.fullmatch(r'model-selection20260908-[A-Za-z0-9_-]+', payload.name) or manifest['remote_payload'] != str(payload):
    raise SystemExit('Transport destination mismatch')
required = {'AUTHORIZATION.json', 'AUTHORIZED_PROTOCOL.md', 'REMOTE_BASELINE.json', 'STAGE_A_MANIFEST.json', 'payload/stage_A.tar.gz', 'deploy_remote.py', 'study_config.py', 'launch_once.py', 'deploy.sh'}
if set(manifest['files']) != required:
    raise SystemExit('Transport file inventory mismatch')
actual = {p.relative_to(payload).as_posix() for p in payload.rglob('*') if not p.is_dir()}
if actual != required | {'TRANSPORT_MANIFEST.json', 'launch.sh'}:
    raise SystemExit('Unexpected transport file')
for name, expected in manifest['files'].items():
    path = payload / name
    if path.is_symlink() or not path.is_file() or path.resolve() != path:
        raise SystemExit('Unsafe transport file')
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit('Transport content mismatch: ' + name)
PY
exec /data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B "$PAYLOAD/deploy_remote.py" --payload "$PAYLOAD" --stage A --submit
