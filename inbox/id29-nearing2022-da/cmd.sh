#!/bin/bash
# ID29 seq=107: deploy the Git-1.8-compatible, locally frozen closure bytes; preserve prior attempts; submit final preclosure.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
CHANNEL="$HOME/hpc_mailbox/inbox/id29-nearing2022-da"
PAYLOAD="$CHANNEL/payload.tar.gz"
PAYLOAD_SHA=0c900f98ba0399b5e8de08761a57adfcc1c687f436c5cce4eb5f485f89ce6224
PROVENANCE="$ROOT/closure_20260810/provenance"
STAGE="$ROOT/closure_20260810/deployment/seq107"
BACKUP_ROOT="$PROVENANCE/preclosure_payload_seq107_backups"
PAYLOAD_COPY="$PROVENANCE/preclosure_payload_seq107.tar.gz"
DEPLOYMENT_RECEIPT="$PROVENANCE/preclosure_payload_seq107_receipt.json"
ATTEMPT_RECEIPT="$PROVENANCE/preclosure_failed_attempts_through_202373.json"
JOB_RECEIPT="$PROVENANCE/preclosure_validation_seq107_job.txt"
VALIDATION="$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"

RELATIVE_PATHS=(
  test/test_nearing2022_reproduction_contract.py
  src/29_nearing2022_da_ar/scripts/verify_registered_closure.py
  src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm
  src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm
  src/29_nearing2022_da_ar/reference/local_contract_validation_junit.xml
  src/29_nearing2022_da_ar/reference/local_contract_validation.json
  src/29_nearing2022_da_ar/reference/local_contract_validation_junit_pre_git_compat_20260810.xml
  src/29_nearing2022_da_ar/reference/local_contract_validation_pre_git_compat_20260810.json
)
NEW_SHAS=(
  8896fe1f7437789ac14087d8b67cc68e11b4bff6d806e24bcd0cd263530b1b4a
  c4487ffb1a4ba151dbc782830fb6209e2eae62666fb0819179dad632fae351db
  a66e9eb6777686ad21f870cd30d6832057b62128c8cc563eb14faff2b3ed15f0
  0233e11c0f7e14364550abde802d2af7e9279cb6b0a612ea336f088c144151e0
  3224f75cb2a8c28d80b94055fe143278b07e52c667386ff8241eedae7679db01
  62c11fb1cdd1aa1545cc073c178049e704369b36ac7152b9f8d31f9ee9ae7a7e
  0e3c85f240617cacf1b0908cb827975b510a2fc5892bace7b7ba75c14e39c747
  70b86ac597d1512122f8a56315d6f1cddeda5889572b0e3bcdaa18d1272333fb
)
OLD_SHAS=(
  46d232a19aef3f53719bc3b24daf7c067512730e0485905964fb5e895c213495
  b7de3e94afccf5648edfec91036721d3fd594ef566cea0cd92b0491752665e21
  bf6dd27da64e6a4d1af1bd4adefce37cce033ad5bcd97d82b2f0d1717d8c0c89
  2cb9a513fc3a489622938d3b9f0a8fe1a0b6f093f1f584419e266453cb887803
  0e3c85f240617cacf1b0908cb827975b510a2fc5892bace7b7ba75c14e39c747
  70b86ac597d1512122f8a56315d6f1cddeda5889572b0e3bcdaa18d1272333fb
)

echo "=== PRE-INSTALL SAFETY BOUNDARY ==="
test -f "$PAYLOAD"
echo "$PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
mapfile -t MEMBERS < <(tar -tzf "$PAYLOAD")
test "${#MEMBERS[@]}" -eq "${#RELATIVE_PATHS[@]}"
for index in "${!RELATIVE_PATHS[@]}"; do
  test "${MEMBERS[$index]}" = "${RELATIVE_PATHS[$index]}"
done
test "$(sacct -n -P -j 202373 --format=JobIDRaw,State | awk -F'|' '$1 == "202373" {print $2; exit}')" = "FAILED"
test -z "$(squeue -h -n N22-preclosure-check -o '%i')"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
test ! -e "$STAGE"
test ! -e "$BACKUP_ROOT"
test ! -e "$PAYLOAD_COPY"
test ! -e "$DEPLOYMENT_RECEIPT"
test ! -e "$ATTEMPT_RECEIPT"
test ! -e "$JOB_RECEIPT"

for index in "${!OLD_SHAS[@]}"; do
  target="$ROOT/${RELATIVE_PATHS[$index]}"
  test -f "$target"
  test "$(sha256sum "$target" | awk '{print $1}')" = "${OLD_SHAS[$index]}"
done
for index in 6 7; do
  test ! -e "$ROOT/${RELATIVE_PATHS[$index]}"
done

echo "=== STAGE AND VERIFY PAYLOAD ==="
mkdir -p "$STAGE" "$BACKUP_ROOT"
tar -xzf "$PAYLOAD" -C "$STAGE"
for index in "${!RELATIVE_PATHS[@]}"; do
  staged="$STAGE/${RELATIVE_PATHS[$index]}"
  test -f "$staged"
  test "$(sha256sum "$staged" | awk '{print $1}')" = "${NEW_SHAS[$index]}"
done
install -m 0644 "$PAYLOAD" "$PAYLOAD_COPY"
echo "$PAYLOAD_SHA  $PAYLOAD_COPY" | sha256sum -c -

echo "=== PRESERVE AND ATOMICALLY INSTALL ==="
for index in "${!RELATIVE_PATHS[@]}"; do
  relative="${RELATIVE_PATHS[$index]}"
  target="$ROOT/$relative"
  staged="$STAGE/$relative"
  if [ "$index" -lt 6 ]; then
    backup="$BACKUP_ROOT/$relative"
    mkdir -p "$(dirname "$backup")"
    install -m 0644 "$target" "$backup"
    test "$(sha256sum "$backup" | awk '{print $1}')" = "${OLD_SHAS[$index]}"
  fi
  mkdir -p "$(dirname "$target")"
  temporary="$target.seq107.tmp"
  test ! -e "$temporary"
  install -m 0644 "$staged" "$temporary"
  test "$(sha256sum "$temporary" | awk '{print $1}')" = "${NEW_SHAS[$index]}"
  mv "$temporary" "$target"
  test "$(sha256sum "$target" | awk '{print $1}')" = "${NEW_SHAS[$index]}"
done
python -m py_compile "$ROOT/src/29_nearing2022_da_ar/scripts/verify_registered_closure.py"
bash -n "$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"
bash -n "$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm"
grep -q '#SBATCH --nodelist=ngu003' "$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"
grep -q '#SBATCH --nodelist=ngu003' "$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm"
grep -Fq -- '--extra-tree "$PROVENANCE"' "$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm"

echo "=== PRESERVE ALL FAILED PRECLOSURE ATTEMPTS ==="
for job in 202365 202369 202370 202373; do
  for extension in out err; do
    source_log="$ROOT/closure_20260810/logs/N22-preclosure-check_${job}.${extension}"
    preserved_log="$PROVENANCE/preclosure_attempt_${job}.${extension}"
    test -f "$source_log"
    test ! -e "$preserved_log"
    install -m 0644 "$source_log" "$preserved_log"
    test "$(sha256sum "$source_log" | awk '{print $1}')" = "$(sha256sum "$preserved_log" | awk '{print $1}')"
  done
done

python - "$ROOT" "$STAGE" "$BACKUP_ROOT" "$PAYLOAD_COPY" "$DEPLOYMENT_RECEIPT" "$ATTEMPT_RECEIPT" "${RELATIVE_PATHS[@]}" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root, stage, backup_root, payload_copy, deployment_receipt, attempt_receipt = map(Path, sys.argv[1:7])
relative_paths = sys.argv[7:]

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

files = []
for index, relative in enumerate(relative_paths):
    target = root / relative
    staged = stage / relative
    item = {
        'path': relative,
        'installed_bytes': target.stat().st_size,
        'installed_sha256': digest(target),
        'staged_sha256': digest(staged),
    }
    assert item['installed_sha256'] == item['staged_sha256']
    backup = backup_root / relative
    if backup.is_file():
        item['backup'] = str(backup)
        item['backup_bytes'] = backup.stat().st_size
        item['backup_sha256'] = digest(backup)
    files.append(item)

deployment = {
    'schema': 'nearing2022-preclosure-payload-deployment-v1',
    'mailbox_seq': 107,
    'created_utc': datetime.now(timezone.utc).isoformat(),
    'payload_copy': str(payload_copy),
    'payload_bytes': payload_copy.stat().st_size,
    'payload_sha256': digest(payload_copy),
    'files': files,
}
temporary = deployment_receipt.with_suffix(deployment_receipt.suffix + '.tmp')
assert not deployment_receipt.exists() and not temporary.exists()
temporary.write_text(json.dumps(deployment, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
temporary.replace(deployment_receipt)
print(json.dumps(deployment, sort_keys=True))

attempts = []
for job in ('202365', '202369', '202370', '202373'):
    records = subprocess.run(
        ['sacct', '-n', '-P', '-j', job, '--format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList'],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    record = next(line.split('|') for line in records if line.split('|', 1)[0].strip() == job)
    keys = ('job_id', 'job_name', 'state', 'exit_code', 'elapsed', 'start', 'end', 'node_list')
    slurm = dict(zip(keys, record, strict=True))
    assert slurm['state'] == 'FAILED'
    out = root / f'closure_20260810/provenance/preclosure_attempt_{job}.out'
    err = root / f'closure_20260810/provenance/preclosure_attempt_{job}.err'
    attempts.append({
        'slurm': slurm,
        'stdout': str(out),
        'stdout_bytes': out.stat().st_size,
        'stdout_sha256': digest(out),
        'stderr': str(err),
        'stderr_bytes': err.stat().st_size,
        'stderr_sha256': digest(err),
    })
attempt_payload = {
    'schema': 'nearing2022-preclosure-failed-attempt-inventory-v1',
    'created_utc': datetime.now(timezone.utc).isoformat(),
    'attempts': attempts,
}
temporary = attempt_receipt.with_suffix(attempt_receipt.suffix + '.tmp')
assert not attempt_receipt.exists() and not temporary.exists()
temporary.write_text(json.dumps(attempt_payload, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
temporary.replace(attempt_receipt)
print(json.dumps(attempt_payload, sort_keys=True))
PY

echo "=== SUBMIT FINAL PRECLOSURE VALIDATION ==="
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
sha256sum "$PAYLOAD_COPY" "$DEPLOYMENT_RECEIPT" "$ATTEMPT_RECEIPT" "$JOB_RECEIPT" "$VALIDATION"
