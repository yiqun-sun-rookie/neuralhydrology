#!/bin/bash
# Final state of array 216811; if all 16 tasks completed and no evaluation exists yet,
# submit the stage-1 evaluation job. Login node only writes the script and submits.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
RUNS=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826/runs
OUTJ=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826/seedbatch_stage1_2023.json
echo "=== A. final state counts ==="
sacct -j 216811 -X --format=State%20 --noheader 2>&1 | sort | uniq -c || true
echo "=== B. per-task ==="
sacct -j 216811 -X --format=JobID%16,State%12,ExitCode%8,Elapsed%10 --noheader 2>&1 | head -20 || true
echo "=== C. run dirs + manifest count ==="
ls $RUNS 2>&1 | head -20 || true
echo "manifests: $(ls $RUNS/*/run_manifest.json 2>/dev/null | wc -l)"
echo "=== D. selection scores ==="
for d in $RUNS/*/; do
  m=$d/run_manifest.json
  if [ -f "$m" ]; then
    python -c "
import json
d=json.load(open('$m'))
print('%-30s arm=%-11s ls=%-2s upd=%-4s sel_mse=%.6f' % ('$(basename $d)', d['arm_id'], d.get('learning_seed','?'), d['best_update'], d['best_selection_mse']))
" 2>&1
  fi
done | sort || true
echo "=== E. failures ==="
for f in $ROOT/logs/kuwei-jdl-s1-216811_*.err; do
  if [ -s "$f" ]; then echo "--- $f ---"; tail -4 "$f"; fi
done 2>&1 | head -20 || true
echo "=== F. evaluation ==="
NDONE=$(ls $RUNS/*/run_manifest.json 2>/dev/null | wc -l)
if [ -f "$OUTJ" ]; then
  echo "evaluation already exists; not resubmitting"
elif [ "$NDONE" -eq 16 ]; then
  cat > $ROOT/seedbatch_eval.slurm <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J kuwei-jdl-eval
#SBATCH -p hcpu48,hcpu48y
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=2
#SBATCH -t 04:00:00
#SBATCH -o logs/kuwei-jdl-eval-%j.out
#SBATCH -e logs/kuwei-jdl-eval-%j.err
set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
export KUWEI_LAOS_ROOT=$ROOT/laos
export KUWEI_FSL_ROOT=$ROOT/fsl
cd $ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts
echo "[$(date)] node=$(hostname)"
python -u kuwei_jdl_seedbatch_evaluate.py
echo "[$(date)] done"
SLURM
  cd $ROOT && sbatch seedbatch_eval.slurm 2>&1 | tee $ROOT/eval_jobid.txt || echo "sbatch FAILED"
else
  echo "only $NDONE/16 manifests; not submitting evaluation"
fi
echo "=== DONE ==="
