#!/usr/bin/env bash
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819
SCRIPT=/data1/home/sunyiq/hpc_mailbox/inbox/zhenjiang-stage-r2/environment_probe.slurm
JOB_FILE="$ROOT/migration/environment_probe_jobid"

echo "=== ENVIRONMENT PROBE PREFLIGHT ==="
test -d "$ROOT/payload_frozen" || { echo "PAYLOAD_ROOT_MISSING"; exit 1; }
test -f "$ROOT/migration/acceptance_jobid" || { echo "FIRST_ACCEPTANCE_JOB_ID_MISSING"; exit 1; }
test ! -e "$ROOT/migration/hpc_acceptance.json" || { echo "UNEXPECTED_ACCEPTANCE_JSON_EXISTS"; exit 1; }
test -f "$SCRIPT" || { echo "PROBE_SCRIPT_MISSING"; exit 1; }
test ! -e "$JOB_FILE" || { echo "ENVIRONMENT_PROBE_ALREADY_SUBMITTED"; exit 1; }

echo "=== SUBMIT READ-ONLY ENVIRONMENT PROBE ==="
PROBE_JOB_ID=$(sbatch --parsable "$SCRIPT") || exit 1
( set -o noclobber; printf '%s\n' "$PROBE_JOB_ID" > "$JOB_FILE" ) || {
    echo "PROBE_JOB_ID_RECORD_FAILED"
    exit 1
}
echo "environment_probe_jobid=$PROBE_JOB_ID"

echo "=== WAIT ENVIRONMENT PROBE (max 10 min) ==="
COUNT=0
while [ "$COUNT" -lt 120 ]; do
    STATE=$(sacct -j "$PROBE_JOB_ID" --noheader -X --format=State | awk 'NF {print $1; exit}')
    case "$STATE" in
        COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL)
            break
            ;;
    esac
    sleep 5
    COUNT=$((COUNT + 1))
done

echo "=== PROBE SACCT ==="
sacct -j "$PROBE_JOB_ID" -X --format=JobID,JobName,NodeList,State,ExitCode,Elapsed
echo "=== PROBE STDOUT ==="
cat "$ROOT/logs/environment_probe_${PROBE_JOB_ID}.out" 2>/dev/null || true
echo "=== PROBE STDERR ==="
cat "$ROOT/logs/environment_probe_${PROBE_JOB_ID}.err" 2>/dev/null || true
echo "=== END ==="
