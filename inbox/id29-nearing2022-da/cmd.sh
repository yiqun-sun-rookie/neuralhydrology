#!/bin/bash
# ID29 seq=94: deploy immutable preclosure validators and offline source evidence, then submit a CPU validation job; keep candidate manifest 202293 held.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD="$HOME/hpc_mailbox/inbox/id29-nearing2022-da/payload.tar.gz"
PAYLOAD_SHA=e012be8ce1fdd0be232547ff40655ab97c31ec9bf60e838e7b56f4c4efda20a4
STAGE="$ROOT/closure_20260810/deployment/seq94"
BACKUP="$ROOT/closure_20260810/provenance/preclosure_seq94_backup"
RECEIPT="$ROOT/closure_20260810/provenance/preclosure_payload_seq94_receipt.json"
JOB_RECEIPT="$ROOT/closure_20260810/provenance/preclosure_validation_seq94_job.txt"
VALIDATION="$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"
GATE_OUTPUT="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
GATE_DETAILS="$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

EXPECTED_MEMBERS=(
  src/29_nearing2022_da_ar/scripts/verify_registered_closure.py
  src/29_nearing2022_da_ar/scripts/independent_verify_closure_export.py
  src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm
  src/29_nearing2022_da_ar/hpc/run_registered_closure_export.slurm
  src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm
  test/test_nearing2022_reproduction_contract.py
  test/test_assimilation.py
  results/29_nearing2022_da_ar/formal_closure/author_release_scope_audit.json
  results/29_nearing2022_da_ar/formal_closure/provenance/local_camels_us_manifest_v2.json
  results/29_nearing2022_da_ar/formal_closure/provenance/hpc_camels_us_manifest_v2.json
  results/29_nearing2022_da_ar/formal_closure/author_source_archives/source_archive_binding.json
  results/29_nearing2022_da_ar/formal_closure/author_source_archives/zenodo-7063252-grey-nearing-lstm-data-assimilation-v1.0.zip
  results/29_nearing2022_da_ar/formal_closure/author_source_archives/zenodo-7063259-grey-nearing-neuralhydrology-public-v.1.3.0.zip
  results/29_nearing2022_da_ar/formal_closure/author_source_archives/github-grey-nearing-neuralhydrology-public-assimilation-a3f8bfc.bundle
)

echo "=== PRE-INSTALL SAFETY BOUNDARY ==="
test -f "$PAYLOAD"
echo "$PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
mapfile -t PAYLOAD_MEMBERS < <(tar -tzf "$PAYLOAD")
test "${#PAYLOAD_MEMBERS[@]}" -eq "${#EXPECTED_MEMBERS[@]}"
for index in "${!EXPECTED_MEMBERS[@]}"; do
  test "${PAYLOAD_MEMBERS[$index]}" = "${EXPECTED_MEMBERS[$index]}"
done
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
GATE_STATE=$(squeue -h -j 202315 -o '%i|%T|%r|%j')
echo "gate_state_before=$GATE_STATE"
test "$GATE_STATE" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$GATE_OUTPUT"
test ! -e "$GATE_DETAILS"

echo "=== STAGE AND ATOMIC INSTALL ==="
if [ ! -f "$RECEIPT" ]; then
  test ! -e "$STAGE"
  mkdir -p "$STAGE"
  tar -xzf "$PAYLOAD" -C "$STAGE"
fi
python - "$ROOT" "$STAGE" "$BACKUP" "$RECEIPT" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys

root, stage, backup, receipt = map(Path, sys.argv[1:5])
expected = {
    'src/29_nearing2022_da_ar/scripts/verify_registered_closure.py': (62198, 'c91b9addebf5b5014fc5c8b2657d4740c836dbf6d91ff960c8e0a69e18f8e291'),
    'src/29_nearing2022_da_ar/scripts/independent_verify_closure_export.py': (9615, '855512b1235ceae3230e6cd67feb1be6350d800f92d53bf8da7d9c949391ce02'),
    'src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm': (8398, '688a07b82342452b0e4619908aa32d6f8fd722acb75724bf7e7af67767562311'),
    'src/29_nearing2022_da_ar/hpc/run_registered_closure_export.slurm': (3902, '9f2b197239d58b8cd0068007645152f890d7173c0e513c4bc3f7214c7dae854b'),
    'src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm': (1487, 'e20f4f7cae88a6e5a04d34ebd27f2dab4e04ef4f1d12a4cc5375b8ba9bafbad9'),
    'test/test_nearing2022_reproduction_contract.py': (67261, 'f29cda3b0a6f820dcf7eb12b6c36fb431a0d82c72107c6f7db5dec30e4786a77'),
    'test/test_assimilation.py': (7208, 'eb4461ff539e223ee7124cba1e78ba3ba3e526aa260516a0f7a687118d25da2d'),
    'results/29_nearing2022_da_ar/formal_closure/author_release_scope_audit.json': (22011, '2d81bee2fc38b43ea85dbaa896b7cf74b7d7b593a28900013fd1d5db19612eeb'),
    'results/29_nearing2022_da_ar/formal_closure/provenance/local_camels_us_manifest_v2.json': (561674, '7fa3afc7fb88c62598ec8c66124118a796ca308345a512b541dc8c0d67a3abc1'),
    'results/29_nearing2022_da_ar/formal_closure/provenance/hpc_camels_us_manifest_v2.json': (561674, 'b0081173696f6c07cbe2e46fded65c08fb9f9ae8f2cbc7b8d44184a0bda80597'),
    'results/29_nearing2022_da_ar/formal_closure/author_source_archives/source_archive_binding.json': (2620, 'abaf1dc519bba8a74bdcf0c8ce4c21e5477d0ec93de90dc1f9a5e78c5389dd44'),
    'results/29_nearing2022_da_ar/formal_closure/author_source_archives/zenodo-7063252-grey-nearing-lstm-data-assimilation-v1.0.zip': (5187841, '5b6ac24a946d3516af6e1f8464ebceed99fd4ee09c6c8a8650a7716338dd7906'),
    'results/29_nearing2022_da_ar/formal_closure/author_source_archives/zenodo-7063259-grey-nearing-neuralhydrology-public-v.1.3.0.zip': (5935555, '91aefc74675aa83d0cc63695a48b69cec89f43605bb68c836424d839d212603d'),
    'results/29_nearing2022_da_ar/formal_closure/author_source_archives/github-grey-nearing-neuralhydrology-public-assimilation-a3f8bfc.bundle': (11639604, 'c8a2e694f68450eca2f8bdfddda28a1468b9033e85ef60563d0b87c168bfadb4'),
}


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def safe_path(relative):
    pure = PurePosixPath(relative)
    assert pure.as_posix() == relative and not pure.is_absolute()
    assert all(part not in {'', '.', '..'} for part in pure.parts)
    return Path(*pure.parts)


if receipt.is_file():
    existing = json.loads(receipt.read_text(encoding='utf-8'))
    assert existing['schema'] == 'nearing2022-preclosure-payload-receipt-v1'
    assert existing['mailbox_seq'] == 94
    assert set(existing['files']) == set(expected)
else:
    files = {}
    for relative, (byte_count, sha256) in expected.items():
        local = safe_path(relative)
        source = stage / local
        destination = root / local
        assert source.is_file() and source.stat().st_size == byte_count and digest(source) == sha256
        previous = None
        if destination.exists():
            assert destination.is_file()
            previous = {'bytes': destination.stat().st_size, 'sha256': digest(destination)}
            if previous['sha256'] != sha256 or previous['bytes'] != byte_count:
                preserved = backup / local
                assert not preserved.exists()
                preserved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(destination, preserved)
                assert preserved.stat().st_size == previous['bytes'] and digest(preserved) == previous['sha256']
        if previous is None or previous['sha256'] != sha256 or previous['bytes'] != byte_count:
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + '.seq94.tmp')
            assert not temporary.exists()
            shutil.copy2(source, temporary)
            assert temporary.stat().st_size == byte_count and digest(temporary) == sha256
            os.replace(temporary, destination)
        assert destination.stat().st_size == byte_count and digest(destination) == sha256
        files[relative] = {'bytes': byte_count, 'sha256': sha256, 'previous': previous}
    payload = {
        'schema': 'nearing2022-preclosure-payload-receipt-v1',
        'mailbox_seq': 94,
        'installed_at': datetime.now(timezone.utc).isoformat(),
        'files': files,
    }
    receipt.parent.mkdir(parents=True, exist_ok=True)
    temporary = receipt.with_suffix(receipt.suffix + '.tmp')
    assert not temporary.exists()
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    os.replace(temporary, receipt)

for relative, (byte_count, sha256) in expected.items():
    destination = root / safe_path(relative)
    assert destination.is_file() and destination.stat().st_size == byte_count and digest(destination) == sha256
print(json.dumps(json.loads(receipt.read_text(encoding='utf-8')), sort_keys=True))
PY

echo "=== INSTALLED STATIC CHECKS ==="
bash -n "$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_numerical_gate.slurm"
bash -n "$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm"
bash -n "$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_closure_export.slurm"
bash -n "$VALIDATION"
python -m json.tool "$ROOT/results/29_nearing2022_da_ar/formal_closure/author_source_archives/source_archive_binding.json" >/dev/null
python -m py_compile "$ROOT/src/29_nearing2022_da_ar/scripts/verify_registered_closure.py"

echo "=== SUBMIT CPU VALIDATION ==="
if [ -f "$JOB_RECEIPT" ]; then
  VALIDATION_JOB_ID=$(tr -d '[:space:]' < "$JOB_RECEIPT")
  test -n "$VALIDATION_JOB_ID"
  scontrol show job -o "$VALIDATION_JOB_ID" >/dev/null 2>&1 || sacct -n -j "$VALIDATION_JOB_ID" --format=JobID | grep -q "$VALIDATION_JOB_ID"
else
  test -z "$(squeue -h -n N22-preclosure-check -o '%i')"
  VALIDATION_JOB_ID=$(sbatch --parsable "$VALIDATION" | cut -d';' -f1)
  test -n "$VALIDATION_JOB_ID"
  printf '%s\n' "$VALIDATION_JOB_ID" > "$JOB_RECEIPT"
fi
echo "validation_job_id=$VALIDATION_JOB_ID"
scontrol show job -o "$VALIDATION_JOB_ID"

echo "=== POST-INSTALL SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
GATE_STATE=$(squeue -h -j 202315 -o '%i|%T|%r|%j')
echo "gate_state_after=$GATE_STATE"
test "$GATE_STATE" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$GATE_OUTPUT"
test ! -e "$GATE_DETAILS"
sha256sum "$PAYLOAD" "$RECEIPT" "$JOB_RECEIPT"
