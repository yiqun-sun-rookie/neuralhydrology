#!/bin/bash
# id26-v09-strict seq=11 : finish watching training 201718, then (only if it completed
# cleanly) submit the independent replay audit and report its verdict.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
REPO=$ROOT/neuralhydrology
D=$REPO/results/26_historical_band_experts/formal_v09
RUN=$D/strict_nesting/R09-NEST-S100
PY=$HOME/miniconda3/envs/nh_final/bin/python
JID=$(cat "$ROOT/train_jobid.txt" 2>/dev/null || echo 201718)

echo "=== A FINISH WATCHING TRAINING $JID (cap 60 min) ==="
SEEN=""
for i in $(seq 1 360); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  CUR=$(ls "$RUN" 2>/dev/null | sort | tr '\n' ' ')
  [ "$CUR" != "$SEEN" ] && { echo "[t=$((i*10))s] run_dir: ${CUR:-<empty>}"; SEEN="$CUR"; }
  [ -z "$ST" ] && { echo "[t=$((i*10))s] job left the queue"; break; }
  [ $((i % 30)) -eq 0 ] && echo "[t=$((i*10))s] state=$ST"
  sleep 10
done

echo "=== B TRAINING ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%10,NodeList%9,State%12,ExitCode%8,Elapsed%12 2>&1

echo "=== C TRAINING STDOUT (tail 45) ==="
tail -45 "$ROOT/logs/train_${JID}.out" 2>&1
echo "=== D TRAINING STDERR (tail 20) ==="
tail -20 "$ROOT/logs/train_${JID}.err" 2>&1

echo "=== E RUN DIR ==="
ls -la "$RUN" 2>&1 | head -15

OK=0
if [ -f "$RUN/manifest.json" ] && [ -f "$RUN/seal.json" ]; then
  echo "=== F MANIFEST VERDICT ==="
  $PY - <<'PY' 2>&1 | tail -22
import json, pathlib
p = pathlib.Path.home()/"v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09/strict_nesting/R09-NEST-S100/manifest.json"
m = json.loads(p.read_text(encoding="utf-8"))
for k in ("schema","status","formal_execution","seed","epochs","batch_size","training_samples",
          "optimizer_steps_per_epoch","optimizer_steps_total","checkpoint_epochs","checkpoint_files",
          "formal_evaluation_observation_reads"):
    print(f"{k:34s} {m.get(k)}")
PY
  ST=$($PY -c "import json,pathlib;print(json.loads(pathlib.Path('$RUN/manifest.json').read_text(encoding='utf-8')).get('status'))" 2>/dev/null)
  [ "$ST" = "strict_nesting_complete" ] && OK=1
fi

if [ "$OK" != "1" ]; then
  echo "=== TRAINING DID NOT COMPLETE CLEANLY -- NOT SUBMITTING THE AUDIT ==="
  echo "=== END ==="; exit 0
fi

echo "=== G WRITE AUDIT SLURM ==="
cat > "$ROOT/jobs/audit.slurm" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J v09audit
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 04:00:00
#SBATCH -o /data1/home/sunyiq/v09_strict/logs/audit_%j.out
#SBATCH -e /data1/home/sunyiq/v09_strict/logs/audit_%j.err

set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export PATH=/data1/home/sunyiq/v09_strict/gitenv/bin:$PATH
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
cd /data1/home/sunyiq/v09_strict/neuralhydrology
export PYTHONPATH=$(pwd):$PYTHONPATH
echo "node=$(hostname) start=$(date -Iseconds)"
nvidia-smi --query-gpu=index,name,memory.free --format=csv,noheader
echo "=== RUN INDEPENDENT REPLAY AUDIT ==="
python -u src/26_historical_band_experts/audit_formal_strict_stage_v09.py
echo "end=$(date -Iseconds)"
SLURM
sed -i 's/\r$//' "$ROOT/jobs/audit.slurm"

echo "=== H SUBMIT AUDIT ==="
cd "$ROOT/jobs"
AJID=$(sbatch --parsable audit.slurm 2>&1)
echo "AUDIT_JOBID=$AJID"
echo "$AJID" > "$ROOT/audit_jobid.txt"

echo "=== I WAIT FOR AUDIT (cap 45 min) ==="
for i in $(seq 1 270); do
  ST=$(squeue -j "$AJID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && { echo "audit finished at t=$((i*10))s"; break; }
  [ $((i % 12)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done

echo "=== J AUDIT ACCOUNTING ==="
sacct -j "$AJID" -X --format=JobID%10,JobName%10,NodeList%9,State%12,ExitCode%8,Elapsed%12 2>&1
echo "=== K AUDIT STDOUT (tail 40) ==="
tail -40 "$ROOT/logs/audit_${AJID}.out" 2>&1
echo "=== L AUDIT STDERR (tail 20) ==="
tail -20 "$ROOT/logs/audit_${AJID}.err" 2>&1

echo "=== M AUDIT REPORT ==="
$PY - <<'PY' 2>&1 | tail -16
import json, pathlib
p = pathlib.Path.home()/"v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09/R09-NEST-S100.strict_nesting_external_audit.json"
if not p.is_file():
    print("NO AUDIT REPORT")
else:
    r = json.loads(p.read_text(encoding="utf-8"))
    for k in ("status","training_samples","checkpoints_verified","permutation_hashes_recomputed",
              "maximum_pair_difference","maximum_reference_difference",
              "formal_evaluation_observation_reads"):
        print(f"{k:36s} {r.get(k)}")
PY
echo "=== END ==="
