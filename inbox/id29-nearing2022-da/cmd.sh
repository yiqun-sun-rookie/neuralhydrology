#!/bin/bash
# ID29 seq=90: read-only verification that the 20 frozen recovered headline artifacts match their three registered server runs; keep candidate manifest 202293 held.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD="$HOME/hpc_mailbox/inbox/id29-nearing2022-da/payload.tar.gz"
PAYLOAD_SHA=ba8f2b9ad879f56c02b1d1a62c3278ad6dd00b91f74ca2a7f6573c2fa489fdf0
MEMBER=src/29_nearing2022_da_ar/reference/headline_artifact_recovery_binding.json

echo "=== SAFETY BOUNDARY ==="
echo "$PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
mapfile -t MEMBERS < <(tar -tzf "$PAYLOAD")
test "${#MEMBERS[@]}" -eq 1
test "${MEMBERS[0]}" = "$MEMBER"
HELD_STATE=$(squeue -h -j 202293 -o '%i|%T|%r|%j')
echo "held_manifest_before=$HELD_STATE"
test "$HELD_STATE" = "202293|PENDING|JobHeldUser|N22-manifest"

echo "=== FROZEN HEADLINE ARTIFACT HASH VERIFICATION ==="
python - "$ROOT" "$PAYLOAD" "$MEMBER" <<'PY'
import csv
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

root = Path(sys.argv[1]).resolve()
payload_path = Path(sys.argv[2])
member_name = sys.argv[3]
with tarfile.open(payload_path, mode='r:gz') as archive:
    stream = archive.extractfile(member_name)
    if stream is None:
        raise SystemExit(f'Cannot read {member_name}')
    binding = json.load(stream)

expected_coordinates = {
    'simulation': ('training', 'N22-TS-SIM-S0'),
    'autoregression': ('training', 'N22-TS-AR-L01-H000-S0'),
    'assimilation': ('evaluation', 'N22-EVAL-TS-DA-L01-TE000-S0'),
}
if binding.get('schema') != 'nearing2022-headline-artifact-recovery-binding-v1':
    raise SystemExit('Unexpected headline binding schema')
conditions = {condition['condition']: condition for condition in binding['conditions']}
coordinates = {
    name: (condition.get('registry_kind'), condition.get('registry_id'))
    for name, condition in conditions.items()
}
if coordinates != expected_coordinates:
    raise SystemExit(f'Frozen coordinates changed: {coordinates}')


def read_registry(path, id_column):
    with path.open('r', encoding='utf-8', newline='') as stream:
        rows = list(csv.DictReader(stream))
    indexed = {row[id_column]: row for row in rows}
    if len(indexed) != len(rows):
        raise SystemExit(f'Duplicate {id_column} in {path}')
    return indexed


registry_root = root / 'src/29_nearing2022_da_ar/registry'
training = read_registry(registry_root / 'experiment_registry.csv', 'exp_id')
evaluations = read_registry(registry_root / 'evaluation_registry.csv', 'eval_id')
verified = []
for name, (kind, identifier) in expected_coordinates.items():
    row = training[identifier] if kind == 'training' else evaluations[identifier]
    run = Path(row['run_dir'])
    run = run if run.is_absolute() else root / run
    run = run.resolve()
    try:
        run.relative_to(root)
    except ValueError as exc:
        raise SystemExit(f'Registered run escapes root: {run}') from exc
    condition = conditions[name]
    files = condition['files']
    if condition.get('file_count') != len(files):
        raise SystemExit(f'File count mismatch in binding: {name}')
    total_bytes = 0
    seen = set()
    for entry in files:
        relative = entry['path']
        pure = PurePosixPath(relative)
        if pure.is_absolute() or pure.as_posix() != relative or any(part in {'', '.', '..'} for part in pure.parts):
            raise SystemExit(f'Unsafe binding path: {relative}')
        if relative in seen:
            raise SystemExit(f'Duplicate binding path: {name}/{relative}')
        seen.add(relative)
        artifact = (run / Path(*pure.parts)).resolve()
        try:
            artifact.relative_to(run)
        except ValueError as exc:
            raise SystemExit(f'Artifact escapes run: {artifact}') from exc
        if not artifact.is_file():
            raise SystemExit(f'Missing artifact: {artifact}')
        byte_count = artifact.stat().st_size
        digest = hashlib.sha256()
        with artifact.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        actual_digest = digest.hexdigest()
        if byte_count != entry['bytes'] or actual_digest != entry['sha256']:
            raise SystemExit(json.dumps({
                'condition': name,
                'path': relative,
                'expected_bytes': entry['bytes'],
                'actual_bytes': byte_count,
                'expected_sha256': entry['sha256'],
                'actual_sha256': actual_digest,
            }, sort_keys=True))
        total_bytes += byte_count
        verified.append({'condition': name, 'path': relative, 'bytes': byte_count, 'sha256': actual_digest})
    if total_bytes != condition.get('total_bytes'):
        raise SystemExit(f'Total byte count mismatch in binding: {name}')

print(json.dumps({
    'schema': binding['schema'],
    'conditions_verified': len(expected_coordinates),
    'files_verified': len(verified),
    'total_bytes_verified': sum(item['bytes'] for item in verified),
    'coordinates': {name: identifier for name, (_, identifier) in expected_coordinates.items()},
    'files': verified,
}, sort_keys=True))
PY

HELD_STATE=$(squeue -h -j 202293 -o '%i|%T|%r|%j')
echo "held_manifest_after=$HELD_STATE"
test "$HELD_STATE" = "202293|PENDING|JobHeldUser|N22-manifest"
