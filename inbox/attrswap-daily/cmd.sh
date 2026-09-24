#!/bin/bash
# seq=89 READ-ONLY first-check probe for stage 3 (after the 2026-09-22 close-out):
# final states of the 47 stage-3 jobs (226245-226287 main batch, 226558-226561 R1), queue empty for pswap3,
# landing runs/ = 33 dirs, logs/jobs.txt = 47 lines, and whether anything in the landing changed after seq 88.
# No sbatch, no scancel, no files written. No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
date "+epoch %s"
ROOT=/data1/home/sunyiq/precip_swap3_daily_2026_09
cd "$ROOT" || { echo "ROOT MISSING"; exit 1; }
J="$(seq -s, 226245 226287),226558,226559,226560,226561"
echo "=== A. sacct 47 jobs (expect 47 rows, all COMPLETED) ==="
S="$(sacct -j "$J" -S 2026-09-15 -X -n -P --format=JobID,JobName%36,State,ExitCode,End 2>&1)"
echo "$S"
echo "  rows: $(grep -c . <<< "$S")"
echo "  state tally:"
awk -F'|' '{c[$3]++} END{for (k in c) print "    " k " " c[k]}' <<< "$S"
echo "=== B. queue (expect no pswap3 rows) ==="
squeue -u "$USER" -o '%.10i %.36j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap3|JOBID'
echo "  pswap3 rows in queue: $(squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -ci pswap3)"
echo "=== C. landing (expect runs/ 33 dirs, jobs.txt 47 lines) ==="
echo "  runs/ dirs: $(find runs -mindepth 1 -maxdepth 1 -type d | wc -l)"
echo "  runs/ test_metrics.csv: $(find runs -name test_metrics.csv | wc -l)"
echo "  logs/jobs.txt lines: $(wc -l < logs/jobs.txt)  sha256_16: $(sha256sum logs/jobs.txt | cut -c1-16)"
echo "  logs/budget_ledger.txt lines: $(wc -l < logs/budget_ledger.txt)  sha256_16: $(sha256sum logs/budget_ledger.txt | cut -c1-16)"
echo "  landing files total: $(find "$ROOT" -type f | wc -l)"
echo "  files modified after 2026-09-20 17:30 (seq 88 receipt time): $(find "$ROOT" -type f -newermt '2026-09-20 17:30' | wc -l)"
find "$ROOT" -type f -newermt '2026-09-20 17:30' | head -20 | sed 's/^/    /'
echo "  newest 3 files:"
find "$ROOT" -type f -exec stat -c '%Y %y %n' {} + | sort -n | tail -3 | cut -d' ' -f2- | sed 's/^/    /'
echo "=== DONE (read-only) ==="
