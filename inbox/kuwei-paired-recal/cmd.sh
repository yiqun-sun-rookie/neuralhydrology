#!/bin/bash
# Wait for the determinism gate (212027). If it passes, immediately launch the six formal runs
# pinned to ONE compute node so numba-compiled code and CPU are identical across all six.
set -o pipefail
ROOT=~/kuwei_paired
GATE=$ROOT/gate
SCR=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts
JOB=$(grep -oE '[0-9]+' $GATE/gate_jobid.txt 2>/dev/null | tail -1)

echo "=== A. wait for gate job $JOB ==="
for i in $(seq 1 220); do
  ST=$(squeue -j $JOB -h -o "%T" 2>/dev/null)
  [ -z "$ST" ] && { echo "gate left queue after ~$((i*20))s"; break; }
  [ $((i % 15)) -eq 0 ] && echo "  t=$((i*20))s state=$ST"
  sleep 20
done
sacct -j $JOB --format=JobID,State,ExitCode,Elapsed,NodeList%10 2>&1 | head -4 || true

echo "=== B. gate verdict ==="
GOUT=$(ls -t $GATE/kuwei-gate-*.out 2>/dev/null | head -1)
VERDICT=FAIL
if [ -n "$GOUT" ]; then
  grep -E 'numpy |ready_for_six|all_identical|population_sha256|trace_digest|objective_calls|seconds_per_objective|Traceback|Error' "$GOUT" | head -25 || true
  if [ -f $ROOT/gate/out/determinism_gate.json ]; then
    python - <<'PY' 2>&1 || true
import json
d=json.load(open("/data1/home/sunyiq/kuwei_paired/gate/out/determinism_gate.json"))
print("HPC all_identical:", d["all_identical"])
print("HPC comparisons  :", sum(1 for v in d["comparisons"].values() if v), "/", len(d["comparisons"]))
print("HPC trace_digest :", d["trace_digest"])
print("HPC population   :", d["population_sha256"])
print("HPC sec/obj call :", d["seconds_per_objective_call"])
print("VERDICT_LINE:", "PASS" if d["all_identical"] else "FAIL")
PY
    grep -q '"all_identical": true' $ROOT/gate/out/determinism_gate.json && VERDICT=PASS
  fi
else
  echo "(no gate stdout)"
fi
echo "GATE_VERDICT=$VERDICT"

echo "=== C. launch six formal runs only if the gate passed ==="
if [ "$VERDICT" != "PASS" ]; then
  echo "gate did not pass -> NOT launching formal runs"
  echo "=== DONE ==="
  exit 0
fi
mkdir -p $ROOT/formal
cat > $ROOT/formal/formal.slurm <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J kuwei-formal
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=14
#SBATCH -t 40:00:00
#SBATCH -o %x-%j.out
#SBATCH -e %x-%j.err
set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
ROOT=$HOME/kuwei_paired
export KUWEI_LAOS_ROOT=$ROOT/laos
export KUWEI_FSL_ROOT=$ROOT/fsl
export PYTHONPATH=$ROOT/fsl:$PYTHONPATH
SCR=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts
OUT=$ROOT/formal/out
mkdir -p $OUT
echo "[$(date)] ALL SIX RUNS ON ONE NODE: $(hostname)"
grep -m1 'model name' /proc/cpuinfo
python -c "import numpy,scipy,numba;print('numpy',numpy.__version__,'scipy',scipy.__version__,'numba',numba.__version__)"

run_one () {
  local ARM=$1 SEED=$2
  python -u -c "
import sys, json, time
sys.path.insert(0, '$SCR')
import deterministic_fsl_calibration_adapter as a
spec = a.CalibrationRunSpec(arm_id='$ARM', seed=$SEED,
                            output_root='$OUT/${ARM}_seed${SEED}',
                            max_iter=400, record_candidates=False)
t0 = time.time()
r = a.run_calibration_arm(spec)
rec = dict(arm='$ARM', seed=$SEED, best_score=r.best_score,
           population_sha256=r.population_sha256, generations=r.generations,
           objective_calls=r.objective_calls, elapsed_seconds=round(r.elapsed_seconds,1),
           meteo_sha256=r.sources.meteo_sha256, discharge_sha256=r.sources.discharge_sha256)
open('$OUT/${ARM}_seed${SEED}.json','w').write(json.dumps(rec, indent=2))
print('FINISHED', '$ARM', $SEED, 'NSE=', r.best_score, 'calls=', r.objective_calls,
      'sec=', round(time.time()-t0,1), flush=True)
" > $OUT/${ARM}_seed${SEED}.log 2>&1
  echo "[$(date)] done ${ARM} seed=${SEED} rc=$?"
}

for SEED in 20260824 20260825 20260826; do
  for ARM in current_input suspect_zero_excluded; do
    run_one $ARM $SEED &
  done
done
wait
echo "[$(date)] ALL SIX COMPLETE"
ls -la $OUT/*.json 2>/dev/null || true
for f in $OUT/*.json; do echo "--- $f"; cat "$f"; done
SLURM
cd $ROOT/formal && sbatch formal.slurm 2>&1 | tee $ROOT/formal/formal_jobid.txt || echo "sbatch FAILED"
squeue -u ${USER} -n kuwei-formal -o "%.10i %.12j %.8T %.10M %R" 2>&1 | head -4 || true
echo "=== DONE ==="
