#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -c 'import hashlib, json, pathlib, tarfile
root = pathlib.Path('"'"'/data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001'"'"')
payload = pathlib.Path('"'"'/data1/home/sunyiq/hpc_mailbox/inbox/hydrol85935-temporal-20261011-001/payload/temporal_v001_2548c5d62ee4.tar.gz'"'"')
expected = '"'"'2548c5d62ee4c9817faf3b5cca265ad1ae9b243d29c65efe880c5bb4cb8a72d4'"'"'
assert hashlib.sha256(payload.read_bytes()).hexdigest() == expected, '"'"'Payload hash mismatch'"'"'
manifest_hash = '"'"'b5a8638cc6df43c8a61f7a6881bc898c34a5ad26f4ccf9aee184da01ec89a882'"'"'
if root.exists():
    assert (root / '"'"'OWNER'"'"').read_text().strip() == '"'"'hydrol85935_temporal_persistence_20261011_001'"'"', '"'"'Existing root owner mismatch'"'"'
    assert hashlib.sha256((root / '"'"'deployment_manifest.json'"'"').read_bytes()).hexdigest() == manifest_hash, '"'"'Existing deployment differs; preserve it'"'"'
else:
    root.mkdir()
    with tarfile.open(payload, '"'"'r:gz'"'"') as archive:
        members = sorted(archive.getmembers(), key=lambda m: m.name == '"'"'deployment_manifest.json'"'"')
        for member in members:
            path = root / member.name
            assert member.isfile() and not pathlib.PurePosixPath(member.name).is_absolute() and path.resolve().is_relative_to(root.resolve()), '"'"'Unsafe archive member'"'"'
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('"'"'xb'"'"') as output:
                output.write(archive.extractfile(member).read())
    assert hashlib.sha256((root / '"'"'deployment_manifest.json'"'"').read_bytes()).hexdigest() == manifest_hash
inventory = json.loads((root / '"'"'deployment_manifest.json'"'"').read_text())
for relative, expected_hash in inventory['"'"'sha256'"'"'].items():
    assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == expected_hash, relative
print(json.dumps({'"'"'status'"'"':'"'"'DEPLOYED_VERIFIED'"'"','"'"'files'"'"':len(inventory['"'"'sha256'"'"']),'"'"'root'"'"':str(root)}))
'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001/code/advance.py --root /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001 --parent /data1/home/sunyiq/hydrol85935_revision_20261008_001 --version v003
