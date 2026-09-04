#!/bin/bash
# seq=461: retry after runner-staging path correction; no server action occurred at seq 460
exec bash "$HOME/hpc_mailbox/inbox/id29-nearing2022-da/deploy_submit_replacement_verifier_seq460.sh"
# The previous read-only preflight remains below as preserved, unreachable channel history.
# seq=459: read-only server preflight for the versioned replacement-chain verifier
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
FORMAL="$ROOT/results/29_nearing2022_da_ar/formal_closure"
DIAG="$FORMAL/diagnostics"
PAIR_PARENT="$DIAG/warmup_pair"
DEPLOY="$FORMAL/warmup_pair_v2_20260904"
RUNBASE="$DIAG/warmup_pair_v2_20260904"

echo "=== TIME AND SOURCE REVISION ==="
date --iso-8601=seconds
git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true
git -C "$ROOT" rev-parse HEAD 2>/dev/null || true
git -C "$ROOT" status --short --untracked-files=no -- neuralhydrology/datasetzoo/basedataset.py 2>/dev/null || true

echo "=== REQUIRED SERVER HASHES ==="
for F in \
  neuralhydrology/datasetzoo/basedataset.py \
  src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py \
  src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py \
  results/29_nearing2022_da_ar/formal_closure/warmup_target_paired_retraining_protocol.json \
  results/29_nearing2022_da_ar/formal_closure/warmup_target_paired_retraining_protocol_amendment_01.json \
  results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_paired_retraining_protocol.json \
  results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_paired_retraining_protocol_amendment_01.json \
  results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_repair_submission_01.json \
  src/29_nearing2022_da_ar/configs/full_reproduction/time_split/autoregression/lead_1_holdout_0.0_seed_0.yml \
  src/29_nearing2022_da_ar/basin_lists/531_basin_list.txt \
  src/29_nearing2022_da_ar/registry/experiment_registry.csv \
  src/29_nearing2022_da_ar/registry/evaluation_registry.csv \
  src/29_nearing2022_da_ar/registry/assimilation_hyperparameter_registry.csv; do
  P="$ROOT/$F"
  if [ -f "$P" ] && [ ! -L "$P" ]; then sha256sum "$P"; else echo "MISSING_OR_NOT_REGULAR $F"; fi
done
echo "warmup-mask occurrences in clean server source:"
grep -n "df_sub.loc\[df_sub.index < start_date, self.cfg.target_variables\] = np.nan" \
  "$ROOT/neuralhydrology/datasetzoo/basedataset.py" 2>/dev/null || echo "NONE"

echo "=== REPLACEMENT OUTPUT MEMBERS ==="
for D in author_v13_training_data_port_all531_v2 author_v13_warmup_isolation_all531_v2; do
  P="$DIAG/$D"
  if [ -d "$P" ] && [ ! -L "$P" ]; then
    echo "DIR $D"
    find "$P" -mindepth 1 -maxdepth 1 -printf '%f|%y|%s\n' 2>/dev/null | sort || true
  else
    echo "MISSING_OR_NOT_DIRECTORY $D"
  fi
done

echo "=== REQUIRED JOB STATES ==="
sacct -j 202510,202511,219423 -X -n -P \
  --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList 2>/dev/null || true

echo "=== CURRENT ID29 QUEUE ==="
squeue -u sunyiq -h -o '%i|%j|%T|%M|%L|%R' 2>/dev/null | grep -E '\|N22-' || echo "NO_N22_JOBS"
echo "conflicting N22-replv2 jobs:"
squeue -u sunyiq -h -o '%i|%j|%T|%R' 2>/dev/null | grep -E '\|N22-replv2\|' || echo "NONE"

echo "=== EXISTING PAIR AND VERSIONED TARGET PATHS ==="
if [ -e "$PAIR_PARENT" ]; then
  echo "PRESENT $PAIR_PARENT"
  find "$PAIR_PARENT" -mindepth 1 -maxdepth 2 -printf '%P|%y|%s\n' 2>/dev/null | sort || true
else
  echo "ABSENT $PAIR_PARENT"
fi
for P in "$DEPLOY" "$RUNBASE" "$RUNBASE/replacement_verification"; do
  [ -e "$P" ] && echo "PRESENT $P" || echo "ABSENT $P"
done
find "$DIAG" -maxdepth 1 -name '.warmup_pair_v2_20260904*' -printf 'STAGING %f|%y|%s\n' 2>/dev/null | sort || true

echo "=== HGPU4 LIVE VIEW ==="
sinfo -p hgpu4 -h -o '%P|%a|%l|%D|%N|%T|%G|%f' 2>/dev/null || true
sinfo -N -p hgpu4 -h -o '%N|%T|%G|%f' 2>/dev/null || true

echo "=== PREFLIGHT SENTINELS ==="
BD=$(sha256sum "$ROOT/neuralhydrology/datasetzoo/basedataset.py" 2>/dev/null | awk '{print $1}')
VR=$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py" 2>/dev/null | awk '{print $1}')
J1=$(sacct -j 202510 -X -n -P --format=JobIDRaw,State,ExitCode 2>/dev/null | awk -F'|' '$1=="202510" {print $2"|"$3}')
J2=$(sacct -j 202511 -X -n -P --format=JobIDRaw,State,ExitCode 2>/dev/null | awk -F'|' '$1=="202511" {print $2"|"$3}')
CONFLICT=$(squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c '^N22-replv2$' || true)
echo "basedataset_exact=$([ "$BD" = 4658816ea3110a1c2efcf54c3dcf00d5c0982459dca4f7ac985beb983b12df0d ] && echo yes || echo no)"
echo "verifier_exact=$([ "$VR" = 0bcabc96f9e702f2317464f1f0123c29d49d5f7f0f972a10ea3e01bbf18fe987 ] && echo yes || echo no)"
echo "job202510=$J1"
echo "job202511=$J2"
echo "deployment_target_absent=$([ ! -e "$DEPLOY" ] && echo yes || echo no)"
echo "run_target_absent=$([ ! -e "$RUNBASE" ] && echo yes || echo no)"
echo "conflicting_job_count=$CONFLICT"
exit 0
