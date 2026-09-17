#!/bin/bash
# Stage-3 SINGLE SUBMISSION (PREREG_20260916 section 9 'submission', D26): everything in one afterok chain.
#   ref gate -> era5l rebuild gate (V25) -> 6 ep60 arms (ref arms after ref gate, era5l arms after the rebuild gate)
#            -> guard T16 (afterok all 6 ep60) ; product gates (afterok ref gate, independent of each other)
#            -> E1 / E2 / R2 arms afterok(guard AND own gate) ; E4 eval afterok(ref gate) ; P7 afterok(ref gate)
# Placeholders __PART__ / __WITH_TAU32__ (0|1) / __E4__ (0|1) / __R2__ (products or empty) are substituted by the deploy
# step's python replacement, never by sed on this file (receipt 56 lesson); un-substituted values ABORT (audit C-1).
# sbatch is the only mutating operation; only the numeric job id is accepted (audit C-6). Job ids -> logs/jobs.txt.
# No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap3_daily_2026_09
PART=__PART__
WITH_TAU32=__WITH_TAU32__
E4=__E4__
R2="__R2__"
ERA5L_V25=617233668e726892
ERA5L_TABLE=5e60c4cb0fc589eb
cd $R || exit 1
echo "=== 0. flags (whitelist, no silent defaults) ==="
echo "  PART=$PART WITH_TAU32=$WITH_TAU32 E4=$E4 R2='$R2'"
case "$PART" in hgpu4|hgpu8) ;; *) echo "ABORT: PART placeholder not substituted / unknown: $PART"; exit 1;; esac
case "$WITH_TAU32" in 0|1) ;; *) echo "ABORT: WITH_TAU32 placeholder not substituted: $WITH_TAU32"; exit 1;; esac
case "$E4" in 0|1) ;; *) echo "ABORT: E4 placeholder not substituted: $E4"; exit 1;; esac
case "$R2" in "__R2""__") echo "ABORT: R2 placeholder not substituted"; exit 1;; esac   # split literal: survives the whole-file substitution (2026-09-17 fix)
for p in $R2; do case "$p" in imerg_refday|imerg_utc|gsmap_refday) ;; *) echo "ABORT: unknown R2 product $p"; exit 1;; esac; done
sub () {  # prints the numeric job id; fails on anything else (wrapper help text, error lines) -- HPC_AGENT_GUIDE section 3
  local out; out=$(sbatch --parsable "$@" 2>&1) || { echo "SBATCH ERROR: $out" >&2; return 1; }
  out=${out%%;*}
  case "$out" in ''|*[!0-9]*) echo "SBATCH REJECTED (no numeric id): $out" >&2; return 1;; esac
  echo "$out"
}
echo "=== A. guards (single submission: runs/ must be empty, no jobs.txt, tables and partitions in place) ==="
[ -d logs ] || { echo "ABORT: logs/ missing (deploy not run?)"; exit 1; }
[ "$(ls runs 2>/dev/null | wc -l)" -eq 0 ] || { echo "ABORT: runs/ not empty"; exit 1; }
[ -f logs/jobs.txt ] && { echo "ABORT: logs/jobs.txt exists (already submitted?)"; exit 1; }
WIN="imerg_e18 imerg_local gsmap_utc"; [ "$WITH_TAU32" = "1" ] && WIN="$WIN imerg_tau32"
NOISE="syn_ln035 syn_ln070 syn_ln140"
for p in $WIN $NOISE daymet_shift1 era5l_refday $R2; do
  [ -f hpc_deploy/${p}_daily_529.csv.gz ] || { echo "ABORT: table missing for $p"; exit 1; }
  echo "  table $p $(sha256sum hpc_deploy/${p}_daily_529.csv.gz | cut -c1-16)"
done
h=$(sha256sum hpc_deploy/era5l_refday_daily_529.csv.gz | cut -c1-16)
[ "$h" = "$ERA5L_TABLE" ] || { echo "ABORT: era5l_refday table sha $h != registered $ERA5L_TABLE"; exit 1; }
for f in pswap3_gate_ref.slurm pswap3_gate_product.slurm pswap3_train.slurm pswap3_train_ep60.slurm pswap3_guard_T16.slurm pswap3_eval_ckpt.slurm pswap3_p7.slurm; do
  grep -q "^#SBATCH -p $PART" hpc_deploy/$f || { echo "ABORT: partition not set in $f"; exit 1; }
done
for p in $WIN $NOISE daymet_shift1 era5l_refday $R2; do [ -f configs/pswap3_smoke_${p}.yml ] || { echo "ABORT: smoke config missing for $p"; exit 1; }; done
echo "=== B. budget ledger (V23; planned = this submission, nothing submitted before, R2 reserve = the R2 arms below) ==="
nwin=$(echo $WIN | wc -w); nr2=$(echo $R2 | wc -w)
n30=$(( 3 * (nwin + 3 + 1 + nr2) ))   # window arms + 3 synthetic + shift1 + R2 arms, 3 seeds each
ngate=$(( 1 + nwin + 3 + 1 + 1 + nr2 ))   # ref gate + product gates (window, noise, shift1, era5l rebuild, R2)
gpuh=$(python -c "print(round($n30*2.0 + 6*4.0 + $E4*2.2 + 0.1*$ngate, 1))")
echo "  30-epoch arms=$n30 (R2 arms $((3*nr2)))  ep60 arms=6  E4=$E4  gates=$ngate  planned GPU hours=$gpuh (limit 100.0)"
echo "  guard T16 and P7 request 1 GPU each for <= 20 min (<= 0.67 h total), registered outside the ledger (PREREG 18.1)"
python -c "import sys; sys.exit(0 if $gpuh <= 100.0 else 1)" || { echo "ABORT: planned GPU hours exceed 100.0"; exit 1; }
echo "=== C. reference gate ==="
gref=$(sub hpc_deploy/pswap3_gate_ref.slurm) || { echo "SBATCH FAILED gate_ref"; exit 1; }
echo "gate_ref $gref" | tee -a logs/jobs.txt
echo "=== D. era5l_refday rebuild gate (V25) + 6 ep60 arms ==="
gera=$(sub --dependency=afterok:$gref --export=ALL,PRODUCT=era5l_refday,KIND=rebuild,V25_HASH=$ERA5L_V25 -J pswap3_gate_era5l_refday hpc_deploy/pswap3_gate_product.slurm) || { echo "SBATCH FAILED gate era5l"; exit 1; }
echo "gate_era5l_refday $gera dep=$gref" | tee -a logs/jobs.txt
ep60=""
for s in 100 200 300; do
  j=$(sub --dependency=afterok:$gref --export=ALL,CFG=pswap3_ep60_ref_daymet_s$s,GATE=gate_ref.txt -J pswap3_ep60_ref_daymet_s$s hpc_deploy/pswap3_train_ep60.slurm) || { echo "SBATCH FAILED ep60 ref s$s"; exit 1; }
  echo "pswap3_ep60_ref_daymet_s$s $j dep=$gref" | tee -a logs/jobs.txt; ep60="$ep60:$j"
  j=$(sub --dependency=afterok:$gera --export=ALL,CFG=pswap3_ep60_era5l_refday_s$s,GATE=gate_ref.txt:gate_era5l_refday.txt -J pswap3_ep60_era5l_refday_s$s hpc_deploy/pswap3_train_ep60.slurm) || { echo "SBATCH FAILED ep60 era5l s$s"; exit 1; }
  echo "pswap3_ep60_era5l_refday_s$s $j dep=$gera" | tee -a logs/jobs.txt; ep60="$ep60:$j"
done
echo "=== E. guard T16 (afterok the 6 ep60 arms) ==="
gguard=$(sub --dependency=afterok$ep60 hpc_deploy/pswap3_guard_T16.slurm) || { echo "SBATCH FAILED guard"; exit 1; }
echo "guard_T16 $gguard dep=$ep60" | tee -a logs/jobs.txt
echo "=== F. product gates + 3 arms each (arms afterok guard AND own gate) ==="
submit_product () {
  p=$1; kind=$2; stem=$3
  g=$(sub --dependency=afterok:$gref --export=ALL,PRODUCT=$p,KIND=$kind -J pswap3_gate_$p hpc_deploy/pswap3_gate_product.slurm) || { echo "SBATCH FAILED gate $p"; exit 1; }
  echo "gate_$p $g kind=$kind" | tee -a logs/jobs.txt
  for s in 100 200 300; do
    j=$(sub --dependency=afterok:$gguard:$g --export=ALL,CFG=${stem}_s$s,GATE=guard_T16_PASS.txt:gate_${p}.txt -J ${stem}_s$s hpc_deploy/pswap3_train.slurm) || { echo "SBATCH FAILED $stem s$s"; exit 1; }
    echo "${stem}_s$s $j dep=$gguard:$g" | tee -a logs/jobs.txt
  done
}
for p in $WIN; do submit_product $p window pswap3_win_$p; done
submit_product daymet_shift1 shift1 pswap3_shift1_daymet
for p in $NOISE; do submit_product $p noise pswap3_$p; done
for p in $R2; do submit_product $p r2 pswap3_win_$p; done   # R2 reserve: full V11 (Stage-2 windows), not rule (f)
if [ "$E4" = "1" ]; then
  echo "=== G. E4 checkpoint re-evaluation (afterok ref gate) ==="
  je=$(sub --dependency=afterok:$gref hpc_deploy/pswap3_eval_ckpt.slurm) || { echo "SBATCH FAILED E4"; exit 1; }
  echo "e4_eval_ckpt $je dep=$gref" | tee -a logs/jobs.txt
fi
echo "=== H. P7 per-hydro-year + baselines on the Stage-2 runs (afterok ref gate; D18) ==="
jp=$(sub --dependency=afterok:$gref hpc_deploy/pswap3_p7.slurm) || { echo "SBATCH FAILED P7"; exit 1; }
echo "p7_hydro_year $jp dep=$gref" | tee -a logs/jobs.txt
echo "=== I. ledger + queue snapshot ==="
expected=$(( 1 + 1 + 6 + 1 + (ngate - 2) + n30 + E4 + 1 ))
n=$(wc -l < logs/jobs.txt)
echo "planned_gpu_hours $gpuh submitted_before 0.0 triggered_reserve_R2_arms $((3*nr2)) jobs_registered $n expected $expected $(date '+%F %T')" | tee logs/budget_ledger.txt
[ "$n" -eq "$expected" ] || echo "WARN: job count mismatch ($n vs $expected)"
squeue -u "$USER" -o '%.10i %.36j %.9T %.10M %.6D %.9P %R' 2>&1 | grep -Ei 'pswap3|JOBID' | head -60
echo "=== J. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
