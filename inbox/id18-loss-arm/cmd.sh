#!/bin/bash
# ID18 seq=23: read-only status, completion, and log audit for the exact E04 jobs.
set -eo pipefail

TARGET=/data1/home/sunyiq/id18_e04_20260809
RESULT=$TARGET/results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482
JOBS=202071,202072,202073,202074,202075,202076,202077,202078,202079,202080,202081,202082,202083

echo "=== TIMESTAMP ==="
date -Is
echo "=== SQUEUE ==="
squeue -j "$JOBS" -o "%.10i %.28j %.10P %.9T %.11M %.6D %R" 2>&1
echo "=== SACCT_PRIMARY_JOBS ==="
sacct -X -j "$JOBS" --format=JobID,JobName%28,Partition,State,Elapsed,ExitCode,NodeList,AllocCPUS,AllocTRES%36,Start,End -P 2>&1

echo "=== FORMAL_COMPLETIONS ==="
find "$RESULT/conceptual" -path '*/completion.json' -type f -printf 'conceptual %TY-%Tm-%TdT%TH:%TM:%TS %p\n' 2>/dev/null | sort || true
find "$RESULT/protocol/neural_completions" -name '*.json' -type f -printf 'neural %TY-%Tm-%TdT%TH:%TM:%TS %p\n' 2>/dev/null | sort || true

echo "=== LOG_SIZES ==="
for job_id in 202071 202072 202073 202074 202075 202076; do
    stat -c "%n size=%s modified=%y" "$TARGET/logs/conceptual-${job_id}.out" "$TARGET/logs/conceptual-${job_id}.err" 2>/dev/null || true
done
for job_id in 202077 202078 202079 202080 202081 202082; do
    stat -c "%n size=%s modified=%y" "$TARGET/logs/neural-${job_id}.out" "$TARGET/logs/neural-${job_id}.err" 2>/dev/null || true
done
stat -c "%n size=%s modified=%y" "$TARGET/logs/score-202083.out" "$TARGET/logs/score-202083.err" 2>/dev/null || true

echo "=== NONEMPTY_ERROR_LOGS ==="
found_error=0
for path in "$TARGET"/logs/conceptual-{202071,202072,202073,202074,202075,202076}.err \
            "$TARGET"/logs/neural-{202077,202078,202079,202080,202081,202082}.err \
            "$TARGET"/logs/score-202083.err; do
    if test -s "$path"; then
        found_error=1
        echo "--- $path ---"
        tail -40 "$path"
    fi
done
if test "$found_error" -eq 0; then
    echo "none"
fi
