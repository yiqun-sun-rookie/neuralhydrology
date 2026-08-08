#!/bin/bash
# Submit the 20-cell ID17 gate matrix (5 folds x 2 seeds x {EA-LSTM, FiLM-LSTM input-site}).
set -o pipefail
cd ~/id17_film_gate || exit 1

echo "=== A. UPDATE + REGENERATE CONFIGS ==="
git fetch -q origin "+hpc/id17-film-gate:refs/remotes/origin/hpc/id17-film-gate" 2>&1 | tail -1
git reset -q --hard refs/remotes/origin/hpc/id17-film-gate
git log --oneline -1
sed -i 's/\r$//' src/static_falsification/hpc/*.slurm
mkdir -p logs/17_entity_awareness_hypernet results/17_entity_awareness_hypernet
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final >/dev/null 2>&1
python src/static_falsification/hpc/gen_configs.py 2>&1 | head -2
echo "gate configs: $(ls src/static_falsification/configs/hpc_gate/*.yml | wc -l)"

echo "=== B. SUBMIT ARRAY ==="
JID=$(sbatch --parsable src/static_falsification/hpc/submit_gate_matrix.slurm 2>&1)
echo "array_jobid=$JID"

echo "=== C. QUEUE STATE (30s later) ==="
sleep 30
squeue -u "$USER" -o "%.14i %.12j %.9P %.8T %.10M %R" 2>&1 | head -25
echo "--- my array only ---"
squeue -j "$JID" -h -o "%.14i %.8T %R" 2>&1 | head -10
echo "mine running: $(squeue -j $JID -h -t R 2>/dev/null | wc -l)  pending: $(squeue -j $JID -h -t PD 2>/dev/null | wc -l)"
echo "a02 jobs still up: $(squeue -u $USER -h -n a02_sam_s47,a02_pre_s47 2>/dev/null | wc -l) (untouched)"
