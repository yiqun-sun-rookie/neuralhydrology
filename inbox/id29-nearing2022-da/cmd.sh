#!/bin/bash
# ID29 seq=98: deploy the no-pytest server checker and its exact local test receipt, then submit a replacement CPU validation job.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD="$HOME/hpc_mailbox/inbox/id29-nearing2022-da/payload.tar.gz"
PAYLOAD_SHA=c2cfac9419181f9a47c4a009d1ca2fea2e612d1395b4fab084bafa30654bc891
STAGE="$ROOT/closure_20260810/deployment/seq98"
BACKUP="$ROOT/closure_20260810/provenance/preclosure_seq98_backup"
RECEIPT="$ROOT/closure_20260810/provenance/preclosure_payload_seq98_receipt.json"
JOB_RECEIPT="$ROOT/closure_20260810/provenance/preclosure_validation_seq98_job.txt"
VALIDATION="$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"

EXPECTED_MEMBERS=(
  src/29_nearing2022_da_ar/scripts/verify_registered_closure.py
  src/29_nearing2022_da_ar/scripts/run_server_preclosure_check.py
  src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm
  src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm
  test/test_nearing2022_reproduction_contract.py
  src/29_nearing2022_da_ar/reference/local_contract_validation.json
  src/29_nearing2022_da_ar/reference/local_contract_validation_junit.xml
  results/29_nearing2022_da_ar/formal_closure/reproduction_comparison_register.json
  results/29_nearing2022_da_ar/formal_closure/continuation_state.json
  results/29_nearing2022_da_ar/formal_closure/final_reproduction_report.md
  results/29_nearing2022_da_ar/reproduction_audit.md
  results/29_nearing2022_da_ar/formal_closure/author_reference_b254529/zero_lag_zero_holdout_metrics_table.txt
  results/29_nearing2022_da_ar/formal_closure/headline_three_arm_vs_paper.csv
)

echo "=== PRE-INSTALL SAFETY BOUNDARY ==="
test -f "$PAYLOAD"
echo "$PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
mapfile -t PAYLOAD_MEMBERS < <(tar -tzf "$PAYLOAD")
test "${#PAYLOAD_MEMBERS[@]}" -eq "${#EXPECTED_MEMBERS[@]}"
for index in "${!EXPECTED_MEMBERS[@]}"; do
  test "${PAYLOAD_MEMBERS[$index]}" = "${EXPECTED_MEMBERS[$index]}"
done
test "$(sacct -n -P -j 202365 --format=JobIDRaw,State | awk -F'|' '$1 == "202365" {print $2; exit}')" = "FAILED"
test -z "$(squeue -h -n N22-preclosure-check -o '%i')"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

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
    'src/29_nearing2022_da_ar/scripts/verify_registered_closure.py': (62472, 'b7de3e94afccf5648edfec91036721d3fd594ef566cea0cd92b0491752665e21'),
    'src/29_nearing2022_da_ar/scripts/run_server_preclosure_check.py': (8692, '17463a5ab783d024def54993b0d04cbd37a4f655fbfd4f696da57d7c5251cea8'),
    'src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm': (8440, '2cb9a513fc3a489622938d3b9f0a8fe1a0b6f093f1f584419e266453cb887803'),
    'src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm': (1618, 'bf6dd27da64e6a4d1af1bd4adefce37cce033ad5bcd97d82b2f0d1717d8c0c89'),
    'test/test_nearing2022_reproduction_contract.py': (68460, '46d232a19aef3f53719bc3b24daf7c067512730e0485905964fb5e895c213495'),
    'src/29_nearing2022_da_ar/reference/local_contract_validation.json': (3517, '70b86ac597d1512122f8a56315d6f1cddeda5889572b0e3bcdaa18d1272333fb'),
    'src/29_nearing2022_da_ar/reference/local_contract_validation_junit.xml': (9288, '0e3c85f240617cacf1b0908cb827975b510a2fc5892bace7b7ba75c14e39c747'),
    'results/29_nearing2022_da_ar/formal_closure/reproduction_comparison_register.json': (33768, 'd31991cda016671b31d88670f34961a046728b9be41653fb10d823b4b2529c99'),
    'results/29_nearing2022_da_ar/formal_closure/continuation_state.json': (24004, '8273b9e5cbfa99fbe691154938483c15468c46b2bcecd014f42d6e5961f5aaff'),
    'results/29_nearing2022_da_ar/formal_closure/final_reproduction_report.md': (16777, '487eb90232321eeaea95a6d2be7dbc46008731a71995c91ca51ded24a5ba3464'),
    'results/29_nearing2022_da_ar/reproduction_audit.md': (14622, 'd2293f4823050a24953eeb05c0c4773bf9368432ea04ed27413a7a8751ef0df4'),
    'results/29_nearing2022_da_ar/formal_closure/author_reference_b254529/zero_lag_zero_holdout_metrics_table.txt': (694, '545e7bd0f3d6670e4576401e93134f210c580de3e471d4ad141a513e13cf723d'),
    'results/29_nearing2022_da_ar/formal_closure/headline_three_arm_vs_paper.csv': (611, '519c28b4251313e636f2931ad987f13685eecbb28aee70688bfe20b8adf9bd4e'),
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
    assert existing['mailbox_seq'] == 98
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
            temporary = destination.with_name(destination.name + '.seq98.tmp')
            assert not temporary.exists()
            shutil.copy2(source, temporary)
            assert temporary.stat().st_size == byte_count and digest(temporary) == sha256
            os.replace(temporary, destination)
        assert destination.stat().st_size == byte_count and digest(destination) == sha256
        files[relative] = {'bytes': byte_count, 'sha256': sha256, 'previous': previous}
    payload = {
        'schema': 'nearing2022-preclosure-payload-receipt-v1',
        'mailbox_seq': 98,
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
bash -n "$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm"
bash -n "$VALIDATION"
python -m py_compile \
  "$ROOT/src/29_nearing2022_da_ar/scripts/verify_registered_closure.py" \
  "$ROOT/src/29_nearing2022_da_ar/scripts/run_server_preclosure_check.py"
python -m json.tool "$ROOT/src/29_nearing2022_da_ar/reference/local_contract_validation.json" >/dev/null

echo "=== SUBMIT REPLACEMENT CPU VALIDATION ==="
test ! -e "$JOB_RECEIPT"
VALIDATION_JOB_ID=$(sbatch --parsable "$VALIDATION" | cut -d';' -f1)
test -n "$VALIDATION_JOB_ID"
printf '%s\n' "$VALIDATION_JOB_ID" > "$JOB_RECEIPT"
echo "validation_job_id=$VALIDATION_JOB_ID"
scontrol show job -o "$VALIDATION_JOB_ID"

echo "=== POST-INSTALL SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
sha256sum "$PAYLOAD" "$RECEIPT" "$JOB_RECEIPT"
