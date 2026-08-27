#!/bin/bash
# nature1st-attr-swap seq=109 -- armJ (china min15): submit seeds 43 & 44
# s42 finished COMPLETED, verdict INCONCLUSIVE -> pre-registered branch 3.
# NO set -e. pipefail only. Every grep/tail guarded with || true.
set -o pipefail

RUN=/data1/home/sunyiq/nature_1st
cd "$RUN" || { echo "FATAL: cannot cd $RUN"; exit 1; }
echo "pwd=$(pwd)  date=$(date '+%F %T')"

echo "=== A. VERIFY SBATCH SCRIPTS (sha256 first 16) ==="
for S in 43 44; do
  f="$RUN/scripts/hpc_train_q_armJ_s${S}.sbatch"
  if [ -f "$f" ]; then
    h=$(sha256sum "$f" 2>/dev/null | cut -c1-16 || true)
    echo "  s${S}: present  sha256_16=${h}"
  else
    echo "  s${S}: MISSING $f"
  fi
done
echo "  expected: s43=cbf8ed5c8f1550c2  s44=1f3dba3695439a6d"

echo "=== B. SUBMIT (dedup-guarded; script path only, no CLI options) ==="
for S in 43 44; do
  n=$(squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -c "q_armJ_china_min15_s${S}" || true)
  if [ "${n:-0}" != "0" ]; then echo "  s${S} already queued -- skip"; continue; fi
  if [ -d "models/q_lstm_armJ_hpc_s${S}" ]; then echo "  s${S} output dir exists -- skip"; continue; fi
  f="scripts/hpc_train_q_armJ_s${S}.sbatch"
  if [ ! -f "$f" ]; then echo "  s${S} sbatch script missing -- skip"; continue; fi
  out=$(sbatch "$f" 2>&1)
  echo "  s${S}: $out"
  if echo "$out" | grep -qE 'Submitted batch job [0-9]+'; then
    echo "  s${S}: SUBMIT_OK"
  else
    echo "  s${S}: SUBMIT_FAILED (no 'Submitted batch job <n>' in output)"
  fi
done

echo "=== C. QUEUE AFTER SUBMIT ==="
squeue -u "$USER" -o '%.11i %.26j %.9T %.10M %.9N %.9P' 2>&1 | grep -Ei 'armJ|JOBID' || true

echo "=== D. SACCT (all armJ) ==="
sacct -S 2026-08-27 -u "$USER" -X --format=JobID%11,JobName%26,State%12,ExitCode%8,Elapsed%11,NodeList%9 2>&1 | grep -Ei 'armJ|JobID' || true

echo "=== E. CONFIRM s42 FINAL (sanity re-read) ==="
grep -E 'Done\.|Best val median NSE' "$RUN"/logs/attr_swap/armJ_china_min15*-215195.out 2>/dev/null | tail -3 | sed 's/^/  /' || true

echo "=== F. GPU CAPACITY ==="
sinfo -p hgpu2p,hgpu2,hgpu4 -o '%.10P %.8t %.6D %.20N' 2>&1 | head -20 || true

echo "=== END seq=109 ==="
