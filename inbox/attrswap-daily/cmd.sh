#!/bin/bash
# seq=83 stage-3 SINGLE SUBMISSION (PREREG_20260916 section 9, D26): user release 2026-09-17 "提交" after the seq-82
# deploy receipt (exit 0) and the pre-submission ledger 75.2 GPU h <= 100.0. Runs the substituted
# hpc_deploy/cmd_submit3.sh that the deploy step wrote (PART=hgpu4 WITH_TAU32=1 E4=1 R2='') after checking its hash
# against the locally substituted copy. Expected 43 jobs in one afterok chain. No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
date "+epoch %s"
R=/data1/home/sunyiq/precip_swap3_daily_2026_09
S=$R/hpc_deploy/cmd_submit3.sh
[ -f "$S" ] || { echo "ABORT: $S missing (deploy seq 82 not applied?)"; exit 1; }
h=$(sha256sum "$S" | cut -c1-16)
echo "cmd_submit3.sh sha256[:16] = $h (expect cc227f85eb673450 = local substitution of cmd_submit_template3.sh 7ae81373580ca1a1)"
[ "$h" = "cc227f85eb673450" ] || { echo "ABORT: cmd_submit3.sh differs from the locally substituted copy"; exit 1; }
echo "=== pre: partitions and my queue ==="
sinfo -p hgpu4 -o '%.8P %.6a %.12l %.5D %.10T %N' 2>&1
echo "  my jobs in queue before: $(squeue -u $USER -h 2>/dev/null | wc -l)"
echo "=== run cmd_submit3.sh ==="
bash "$S"
rc=$?
echo "=== cmd_submit3.sh exit code $rc ==="
echo "=== post: jobs.txt ($(wc -l < $R/logs/jobs.txt 2>/dev/null) lines) and ledger ==="
cat $R/logs/jobs.txt 2>/dev/null
cat $R/logs/budget_ledger.txt 2>/dev/null
echo "  my jobs in queue after: $(squeue -u $USER -h 2>/dev/null | wc -l)"
date "+epoch_end %s"
exit $rc
