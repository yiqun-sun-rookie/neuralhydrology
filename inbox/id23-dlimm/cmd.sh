#!/bin/bash
# id23-dlimm seq=1 : environment probe + code fetch. Read-only. No compute, no sbatch.
set -o pipefail

echo "=== SECTION A: network ==="
getent hosts github.com >/dev/null && echo DNS_OK || echo DNS_FAIL
timeout 40 ssh -o ConnectTimeout=25 -T git@github.com 2>&1 | head -1

echo "=== SECTION B: fetch code into ~/id23_dlimm (never touches ~/neuralhydrology) ==="
DEST=$HOME/id23_dlimm
BR=codex/id23-predictive-skill-readout
if [ -d "$DEST/.git" ]; then
  cd "$DEST" || exit 1
  timeout 400 git fetch origin "+refs/heads/$BR:refs/remotes/origin/$BR" 2>&1 | tail -3
  git checkout -q -B work "origin/$BR" 2>&1 | tail -3
else
  timeout 900 git clone --depth 1 --single-branch -b "$BR" \
    git@github.com:yiqun-sun-rookie/neuralhydrology.git "$DEST" 2>&1 | tail -6
  cd "$DEST" || exit 1
fi
echo "head=$(git rev-parse --short HEAD 2>/dev/null)"
echo "pkg_py=$(find src/hbv_history_conditioned_imm -name '*.py' 2>/dev/null | wc -l)"
echo "scl_py=$(find src/scl_hydro -name '*.py' 2>/dev/null | wc -l)"
echo "mlju_py=$(find src/hbv_multilead_joint_uncertainty -name '*.py' 2>/dev/null | wc -l)"

echo "=== SECTION C: conda env nh_final ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
  source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
python -c "import sys,torch,numpy;print('python',sys.version.split()[0]);print('torch',torch.__version__);print('numpy',numpy.__version__);print('cuda_available',torch.cuda.is_available())" 2>&1 | tail -6

echo "=== SECTION D: import smoke (trivial, not compute) ==="
cd "$DEST" || exit 1
PYTHONPATH=$PWD/src timeout 300 python -c "
from hbv_history_conditioned_imm.hbv import forecast_global_state_mode_evolving, forecast_global_state_weighted_parameters
from hbv_history_conditioned_imm.network import HistoryTransitionNetwork
from hbv_history_conditioned_imm.long_history import generate_long_history_parameter_switch_batch
print('imports_ok')
" 2>&1 | tail -8

echo "=== SECTION E: partition state ==="
sinfo -p hgpu2p -o "%P %a %D %t %N" 2>&1 | head -8
echo "=== DONE ==="
