#!/usr/bin/env bash
# zhenjiang-stage-r2 seq=1: immutable payload transfer and compute-node acceptance.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819
MAILBOX=/data1/home/sunyiq/hpc_mailbox
ARCHIVE="$MAILBOX/payload/zhenjiang-stage-r2/datong_stage_direction_r2_hpc_payload_20260819.tar.gz"
BUNDLE="$MAILBOX/payload/zhenjiang-stage-r2/bundle_identity.json"
EXPECTED_ARCHIVE_BYTES=6666393
EXPECTED_ARCHIVE_SHA=599468ee0c5b0892b71cbd146d2ccd737e4bebf894a6b5ed4bafafa2cd4eb958

cd "$MAILBOX" || exit 1

echo "=== MAILBOX PREFLIGHT ==="
test -f "$ARCHIVE" || { echo "ARCHIVE_MISSING"; exit 1; }
test -f "$BUNDLE" || { echo "BUNDLE_IDENTITY_MISSING"; exit 1; }
test "$(wc -c < "$ARCHIVE")" = "$EXPECTED_ARCHIVE_BYTES" || { echo "ARCHIVE_BYTES_MISMATCH"; exit 1; }
test "$(sha256sum "$ARCHIVE" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA" || { echo "ARCHIVE_SHA_MISMATCH"; exit 1; }
test ! -e "$ROOT" || { echo "REMOTE_ROOT_ALREADY_EXISTS"; exit 1; }

echo "=== EXTRACT IMMUTABLE PAYLOAD ==="
mkdir -p "$ROOT/payload_frozen" "$ROOT/logs" "$ROOT/migration"
tar -xzf "$ARCHIVE" -C "$ROOT/payload_frozen"
TAR_EXIT=$?
if [ "$TAR_EXIT" -ne 0 ]; then
    echo "ARCHIVE_EXTRACTION_FAILED exit=$TAR_EXIT"
    exit "$TAR_EXIT"
fi

sed -i 's/\r$//' inbox/zhenjiang-stage-r2/acceptance.slurm

echo "=== SUBMIT ACCEPTANCE ==="
JID=$(sbatch --parsable inbox/zhenjiang-stage-r2/acceptance.slurm 2>&1)
SUBMIT_EXIT=$?
echo "acceptance_jobid=$JID"
if [ "$SUBMIT_EXIT" -ne 0 ]; then
    echo "SBATCH_FAILED exit=$SUBMIT_EXIT"
    exit "$SUBMIT_EXIT"
fi
set -o noclobber
printf '%s\n' "$JID" > "$ROOT/acceptance_job_id.txt"
WRITE_EXIT=$?
set +o noclobber
if [ "$WRITE_EXIT" -ne 0 ]; then
    echo "JOB_ID_RECORD_ALREADY_EXISTS"
    exit "$WRITE_EXIT"
fi

echo "=== WAIT ACCEPTANCE (max 30 min) ==="
for i in $(seq 1 180); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 12)) -eq 0 ] && echo "t=$((i*10))s left=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== ACCEPTANCE SACCT ==="
sacct -j "$JID" -X --format=JobID%12,JobName%14,NodeList%10,State%14,ExitCode%8,Elapsed%10 2>&1 | head -5

echo "=== ACCEPTANCE STDOUT ==="
tail -80 "$ROOT/logs/acceptance_${JID}.out" 2>/dev/null || true
echo "=== ACCEPTANCE STDERR ==="
tail -40 "$ROOT/logs/acceptance_${JID}.err" 2>/dev/null || true
echo "=== ACCEPTANCE JSON ==="
cat "$ROOT/migration/hpc_acceptance.json" 2>/dev/null || true
echo "=== END ==="
