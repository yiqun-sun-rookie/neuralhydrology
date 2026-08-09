#!/usr/bin/env bash
set -eo pipefail

MAILBOX=/data1/home/sunyiq/hpc_mailbox
PAYLOAD="$MAILBOX/payload/kalmannet-tukf06/retry2"
ARCHIVE="$PAYLOAD/TUKF06_FULL_DIAGONAL_SEARCH_HEAD_TO_HEAD_V1.tar.gz"
EXPECTED_SHA=3deb8ff8096eaf32d1c22dd19d51bc30fe59548991fecc8a74e108ad07fc001b
TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
PENDING=/data1/home/sunyiq/kalmannet_tukf06_20260809/.retry2.pending-3deb8ff8

cd "$MAILBOX"
echo "=== DEPLOYMENT INPUT ==="
test -f "$ARCHIVE"
ACTUAL_SHA=$(sha256sum "$ARCHIVE" | awk '{print $1}')
echo "archive_sha256=$ACTUAL_SHA"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "archive hash mismatch" >&2
  exit 51
fi
if [[ -e "$TARGET" ]]; then
  echo "target already exists; refusing deployment: $TARGET" >&2
  exit 52
fi
if [[ -e "$PENDING" ]]; then
  echo "pending target already exists; refusing deployment: $PENDING" >&2
  exit 53
fi

mkdir "$PENDING"
mkdir "$PENDING/source.pending"
tar -xzf "$ARCHIVE" -C "$PENDING/source.pending"
python - "$PENDING/source.pending" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
manifest = json.loads((root / 'bundle_manifest.json').read_text(encoding='utf-8'))
if manifest.get('experiment_id') != 'TUKF06_FULL_DIAGONAL_SEARCH_HEAD_TO_HEAD_V1':
    raise SystemExit('internal experiment identifier mismatch')
for relative, expected in manifest['member_sha256'].items():
    path = root / relative
    if not path.is_file():
        raise SystemExit(f'missing member: {relative}')
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit(f'member hash mismatch: {relative}')
print(f"verified_members={len(manifest['member_sha256'])}")
PY
mv "$PENDING/source.pending" "$PENDING/source"
mkdir "$PENDING/logs" "$PENDING/smoke" "$PENDING/results"
mv "$PENDING" "$TARGET"
echo "deployed_target=$TARGET"

echo "=== DUPLICATE JOB GUARD ==="
if squeue -u "$USER" -h -n tukf06-smoke -o '%i' | grep -q .; then
  echo "an existing tukf06-smoke job is already queued or running" >&2
  exit 54
fi
squeue -u "$USER" -p hcpu48 -o '%.18i %.24j %.10P %.8T %.10M %.20R' | head -30

echo "=== SUBMIT PAID SMOKE ==="
JID=$(sbatch --parsable "$TARGET/source/hpc/tukf06_full_diagonal/submit_smoke_cpu.slurm")
echo "jobid=$JID"
printf '%s\n' "$JID" > "$TARGET/smoke/job_id.txt"

echo "=== WAIT FOR THIS JOB ONLY ==="
for i in $(seq 1 180); do
  if ! squeue -h -j "$JID" -o '%i' 2>/dev/null | grep -q .; then
    break
  fi
  if [[ $((i % 6)) -eq 0 ]]; then
    echo "elapsed_wait_seconds=$((i * 10))"
    squeue -h -j "$JID" -o '%.18i %.24j %.10P %.8T %.10M %.20R'
  fi
  sleep 10
done

echo "=== ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%12,JobName%18,Partition%10,NodeList%12,State%18,ExitCode%8,Elapsed%10,TotalCPU%12,MaxRSS%12
echo "=== STDOUT ==="
tail -120 "$TARGET/logs/smoke-${JID}.out" 2>/dev/null || true
echo "=== STDERR ==="
tail -120 "$TARGET/logs/smoke-${JID}.err" 2>/dev/null || true
echo "=== SMOKE JSON ==="
if [[ ! -f "$TARGET/smoke/smoke_04105700.json" ]]; then
  echo "smoke result is absent" >&2
  exit 55
fi
cat "$TARGET/smoke/smoke_04105700.json"
