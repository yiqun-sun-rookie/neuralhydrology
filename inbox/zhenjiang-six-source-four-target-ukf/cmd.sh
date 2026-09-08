#!/usr/bin/env bash
set -e -o pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1
payload="${HOME}/hpc_mailbox/inbox/zhenjiang-six-source-four-target-ukf/payload/matched_legacy_recovery_20260908_001"
python3 -B - "$payload" <<'PY'
import hashlib, pathlib, runpy, sys
root = pathlib.Path(sys.argv[1])
expected = {'hpc_deployment.py': {'byte_count': 20659, 'sha256': '3daa4fda4c9a7ce4fa3b29fe091035bd5cd13f381bdede80dfdfc4a7ad05019f'}, 'code.tar.gz': {'byte_count': 80581, 'sha256': '94d98c98728b2eab3845624c5c5a8a6ff8b600bbb9c81510f73d0f5d11d5a788'}, 'bundle_manifest.json': {'byte_count': 4019, 'sha256': '145013e4ad0bcb98934a2c36cc07e8ecc4a3c9267c1522a56f262aa30febe6ff'}}
for name, spec in expected.items():
    path = root / name
    if path.is_symlink() or not path.is_file(): raise SystemExit("invalid payload")
    data = path.read_bytes()
    if len(data) != spec["byte_count"] or hashlib.sha256(data).hexdigest() != spec["sha256"]:
        raise SystemExit("payload identity differs")
sys.argv = [str(root / "hpc_deployment.py"), "deploy", "--archive", str(root / "code.tar.gz"),
            "--manifest", str(root / "bundle_manifest.json"), "--manifest-sha256",
            expected["bundle_manifest.json"]["sha256"]]
runpy.run_path(str(root / "hpc_deployment.py"), run_name="__main__")
PY
