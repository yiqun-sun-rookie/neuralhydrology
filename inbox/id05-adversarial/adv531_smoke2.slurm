#!/usr/bin/env bash
# Gate for the only new science code in this campaign: the duration-matched
# random-window control in exp4. One basin, all four windows, both arms.
#SBATCH -J adv531_smoke2
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 01:00:00
#SBATCH -o /data1/home/sunyiq/adv531/logs/smoke2_%j.out
#SBATCH -e /data1/home/sunyiq/adv531/logs/smoke2_%j.err

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd /data1/home/${USER}/adv531
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs results/05_adversarial_robustness/id18_s100_hpc

echo "[$(date)] smoke2: exp4 with the random-window control, 1 basin"
python -c "import torch; print('torch', torch.__version__, '| cuda', torch.cuda.is_available())"

python -u src/adversarial/scripts/run_exp4.py \
    --stride 5 --offset 0 --limit 1 --eps 0.1 --random-control \
    --out results/05_adversarial_robustness/id18_s100_hpc/smoke2_exp4.json

echo "--- what the control produced ---"
python -u - <<'PY'
import json
r = json.load(open("results/05_adversarial_robustness/id18_s100_hpc/smoke2_exp4.json"))[0]
print("basin", r["basin"], "| peaks", r.get("n_peaks"))
print(f"{'window':>7} {'D_peak_pre':>11} {'D_peak_rand':>12} {'days_pre':>9} {'days_rand':>10}")
ok = True
for w in (1, 3, 7, 14):
    dp, dr = r.get(f"D_peak_{w}"), r.get(f"D_peak_rand_{w}")
    np_, nr = r.get(f"n_days_pre_{w}"), r.get(f"n_days_rand_{w}")
    print(f"{w:>7} {dp:11.4f} {dr:12.4f} {np_:9d} {nr:10d}")
    # the control must be exposure-matched to within one window, and both arms
    # must be non-negative by construction (the attacker can always do nothing)
    if abs(np_ - nr) > w or dp < -1e-9 or dr < -1e-9:
        ok = False
print("EXPOSURE-MATCH AND SIGN CHECK:", "PASS" if ok else "FAIL")
PY
echo "[$(date)] smoke2 done"
