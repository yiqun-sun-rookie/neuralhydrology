#!/usr/bin/env bash
# ID33 : clean rerun of the six treatment arms, PACKED three per GPU so each card is loaded.
# The first section is the guard whose absence caused the previous integrity failures.
set -o pipefail
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PKG=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id33_packed_v01.tar.gz
EXPECT=4995a7f265b8cd37dde814797efc924b89ccbc734e01bbad82b1aeba63fc2a4c
echo "=== A. STAMP ==="; date -Is

echo "=== B. IN-FLIGHT GUARD (the step missing last time) ==="
INFLIGHT=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep -c '^id33_' || true)
echo "  running id33 jobs = $INFLIGHT"
if [ "${INFLIGHT:-0}" -gt 0 ]; then
  echo "  REFUSING TO DEPLOY: id33 jobs are in flight and read from the deployment directory."
  squeue -u "$USER" -o "%.9i %.14j %.2t %.11M" 2>&1 | grep -E 'JOBID|id33' || true
  exit 1
fi
echo "  no id33 job in flight; safe to deploy"

echo "=== C. PAYLOAD ==="
test "$(sha256sum "$PKG" 2>/dev/null | cut -d' ' -f1)" = "$EXPECT" && echo PAYLOAD_OK || { echo PAYLOAD_MISMATCH; exit 1; }
cd "$ID33"
tar -xzf "$PKG" && echo extracted
sed -i 's/\r$//' src/transformer_recipe_repair/hpc/*.slurm
sha256sum src/transformer_recipe_repair/hpc/submit_packed_arms.slurm src/transformer_recipe_repair/scripts/run_development.py 2>&1 || true

echo "=== D. PRESERVE THE PREVIOUS RUN DIRECTORIES AS EVIDENCE ==="
R=results/33_transformer_recipe_repair
mkdir -p "$R/_superseded_20260904"
for a in T1 T2 T3 T4 T5 L33; do
  if test -d "$R/$a"; then mv "$R/$a" "$R/_superseded_20260904/$a" && echo "  moved $a aside"; fi
done
mkdir -p "$R/_superseded_20260904/_invocations"
for d in "$R/_invocations"/id33_T?_s100_slurm2204* "$R/_invocations"/id33_T5_s100_slurm2204* "$R/_invocations"/id33_L33_s100_slurm2204*; do
  test -d "$d" && mv "$d" "$R/_superseded_20260904/_invocations/" 2>/dev/null && echo "  moved $(basename $d)"
done
echo "  (C1/C2 left in place: their manifests are COMPLETE)"

echo "=== E. AUDIT ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
export MKL_THREADING_LAYER=GNU
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 || { echo AUDIT_FAILED; exit 1; }

echo "=== F. SUBMIT TWO PACKED JOBS, THREE ARMS PER CARD ==="
SUB=""
for PACK in "T1 T2 T3" "T4 T5 L33"; do
  out=$(ARMS="$PACK" sbatch --export=ALL,ARMS="$PACK"         --job-name="id33_pk" src/transformer_recipe_repair/hpc/submit_packed_arms.slurm 2>&1)
  jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -n "$jid" ]; then echo "  [$PACK] -> $jid"; SUB="$SUB $jid"; else echo "  [$PACK] SUBMIT_FAILED"; echo "$out" | head -4; fi
done
echo "SUBMITTED:$SUB"

echo "=== G. QUEUE ==="
squeue -u "$USER" -o "%.9i %.12j %.9P %.2t %.11M %.16R" 2>&1 | grep -E 'JOBID|id33' || true
echo ID33_PACKED_RERUN_SUBMITTED
