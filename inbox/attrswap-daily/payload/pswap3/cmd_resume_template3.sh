#!/bin/bash
# Stage-3 RESUME (audit C-2): re-submit ONE or more arms after a broken afterok chain (DependencyNeverSatisfied), or
# after the user has ruled on a guard T16 STOP. Nothing here is automatic: every value below is filled by the deploy
# step's python replacement from an explicit user decision, and the command records that decision in logs/resume.txt.
#   __CFGS__      space-separated config stems to (re)submit, e.g. "pswap3_win_imerg_e18_s200 pswap3_syn_ln070_s100"
#   __TEMPLATE__  pswap3_train.slurm | pswap3_train_ep60.slurm
#   __GATES__     colon-separated marker files the arms require (e.g. guard_T16_PASS.txt:gate_imerg_e18.txt)
#   __DEPS__      colon-separated job ids to afterok on, or "none"
#   __OVERRIDE__  "none", or the literal text of the user's ruling when guard T16 returned STOP and the user chose
#                 "FLAG-level continue" (PREREG 5.3): the marker guard_T16_PASS.txt is then written with that text
#                 and every cross-batch head-to-head is degraded to description by precip3_stats.py (T16 FLAG rule).
# Old run dirs of the same stem must have been renamed INCOMPLETE_* beforehand (precip3_stats.py ignores them).
# No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap3_daily_2026_09
CFGS="__CFGS__"
TEMPLATE=__TEMPLATE__
GATES=__GATES__
DEPS=__DEPS__
OVERRIDE="__OVERRIDE__"
cd $R || exit 1
case "$CFGS" in __CFGS__|"") echo "ABORT: CFGS not substituted"; exit 1;; esac
case "$TEMPLATE" in pswap3_train.slurm|pswap3_train_ep60.slurm) ;; *) echo "ABORT: TEMPLATE not substituted / unknown: $TEMPLATE"; exit 1;; esac
case "$GATES" in __GATES__|"") echo "ABORT: GATES not substituted"; exit 1;; esac
case "$DEPS" in __DEPS__) echo "ABORT: DEPS not substituted"; exit 1;; esac
case "$OVERRIDE" in __OVERRIDE__) echo "ABORT: OVERRIDE not substituted"; exit 1;; esac
sub () {
  local out; out=$(sbatch --parsable "$@" 2>&1) || { echo "SBATCH ERROR: $out" >&2; return 1; }
  out=${out%%;*}
  case "$out" in ''|*[!0-9]*) echo "SBATCH REJECTED (no numeric id): $out" >&2; return 1;; esac
  echo "$out"
}
echo "=== A. guards ==="
[ -f logs/jobs.txt ] || { echo "ABORT: no prior submission (logs/jobs.txt missing)"; exit 1; }
for c in $CFGS; do
  [ -f configs/$c.yml ] || { echo "ABORT: config missing $c"; exit 1; }
  live=$(ls -d runs/${c}_* 2>/dev/null | grep -v INCOMPLETE_ | wc -l)
  [ "$live" -eq 0 ] || { echo "ABORT: a live run dir for $c exists (rename it INCOMPLETE_* first)"; exit 1; }
done
if [ "$OVERRIDE" != "none" ]; then
  [ -f logs/guard_T16.json ] || { echo "ABORT: OVERRIDE given but guard_T16.json missing"; exit 1; }
  grep -q '"status": "STOP"' logs/guard_T16.json || { echo "ABORT: OVERRIDE given but guard status is not STOP"; exit 1; }
  echo "T16 FLAG-OVERRIDE by user: $OVERRIDE $(date '+%F %T')" > logs/guard_T16_PASS.txt
  echo "  marker written with the user's ruling (cross-batch head-to-heads become description)"
fi
IFS=':' read -r -a gates <<< "$GATES"
for g in "${gates[@]}"; do [ -f logs/$g ] || { echo "ABORT: gate marker missing: $g"; exit 1; }; done
dep=""; [ "$DEPS" != "none" ] && dep="--dependency=afterok:$DEPS"
echo "=== B. submit ==="
for c in $CFGS; do
  j=$(sub $dep --export=ALL,CFG=$c,GATE=$GATES -J $c hpc_deploy/$TEMPLATE) || { echo "SBATCH FAILED $c"; exit 1; }
  echo "$c $j resume dep=$DEPS gates=$GATES $(date '+%F %T')" | tee -a logs/jobs.txt | tee -a logs/resume.txt
done
echo "resume: cfgs='$CFGS' template=$TEMPLATE deps=$DEPS override='$OVERRIDE' $(date '+%F %T')" >> logs/resume.txt
echo "=== C. ledger note: each resubmitted 30-epoch arm adds 2.0 h, ep60 arm 4.0 h to the V23 account ==="
squeue -u "$USER" -o '%.10i %.36j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap3|JOBID' | head -40
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
