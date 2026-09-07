#!/usr/bin/env bash
set -e -o pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1
payload="${HOME}/hpc_mailbox/inbox/zhenjiang-six-source-four-target-ukf/payload/matched_legacy_20260907_release_001"
python3 -B - "$payload" <<'PY'
import hashlib, pathlib, runpy, sys
root = pathlib.Path(sys.argv[1])
expected = {'hpc_deployment.py': {'byte_count': 20659, 'sha256': '21cb55180b10a84798e40fdfa5a1b1806129c68ce31cba8923399cbc3d1bc50e'}, 'code.tar.gz': {'byte_count': 80534, 'sha256': 'daaa9fcadfddf02a124f5ee26048688b1160f385d976a06f641e326a6f371904'}, 'bundle_manifest.json': {'byte_count': 4019, 'sha256': '779c0964542c561ff6cb6fc160d2999cbc3ef0e6fbf99efac71d0cf886819e30'}}
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
