#!/usr/bin/env bash
#SBATCH -J adv531_smoke
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 01:00:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err
# never write --mem

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd /data1/home/${USER}/adv531
export PYTHONPATH=$(pwd):$PYTHONPATH

echo "=========================================="
echo "[$(date)] adv531 smoke test"
echo "node=$(hostname)  job=$SLURM_JOB_ID"
python --version
python -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else '')"

echo "--- pre-flight ---"
[ -d data/camels_us/basin_mean_forcing/maurer ] || { echo "[FATAL] maurer missing"; exit 1; }
[ -f results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/model_epoch030.pt ] || { echo "[FATAL] checkpoint missing"; exit 1; }
[ -f results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/train_data/train_data_scaler.yml ] || { echo "[FATAL] scaler missing"; exit 1; }
echo "pre-flight OK"

echo "--- header check on the 4 repaired forcing files ---"
for p in 03/02108000 09/05120500 11/07067000 15/09492400; do
  printf "%s: " "$p"
  sed -n '4p' data/camels_us/basin_mean_forcing/maurer/${p}_lump_maurer_forcing_leap.txt | cut -c1-40
done

echo "--- exp2 on the first 3 basins of chunk 0, eps=0.1, all three levels ---"
python -u src/adversarial/scripts/run_exp2.py \
    --stride 5 --offset 0 --limit 3 \
    --epsilons 0.1 --levels lp,physical,statistical \
    --out results/05_adversarial_robustness/id18_s100_hpc/smoke_exp2.json

echo "--- compare against the published per-basin values ---"
python -u - <<'PY'
import json, pathlib
new = {r["basin"]: r for r in json.load(open("results/05_adversarial_robustness/id18_s100_hpc/smoke_exp2.json"))}
ref = json.load(open("reference/smoke_reference.json"))
print(f"{'basin':>10} {'key':>20} {'published':>10} {'hpc':>10} {'diff':>9}")
worst = 0.0
for b, r in ref.items():
    for k, v in r.items():
        got = new.get(b, {}).get(k)
        if got is None:
            print(f"{b:>10} {k:>20} {v:10.4f} {'MISSING':>10}")
            continue
        d = got - v
        worst = max(worst, abs(d))
        print(f"{b:>10} {k:>20} {v:10.4f} {got:10.4f} {d:+9.4f}")
print(f"\nmax abs difference = {worst:.4f}")
print("NOTE: the published run used an unrecorded random start, so exact equality is not expected.")
PY

echo "[$(date)] smoke done"
