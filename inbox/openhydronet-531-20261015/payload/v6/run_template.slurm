#!/usr/bin/env bash
# Copy this file into YOUR project directory and edit every line marked CHANGEME. Do not edit the shared copy.
#SBATCH --job-name=ohn_CHANGEME
#SBATCH -p hgpu4
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 12:00:00
#SBATCH -o PROJECT_ROOT_CHANGEME/logs/%x-%j.out
#SBATCH -e PROJECT_ROOT_CHANGEME/logs/%x-%j.err
# Platform rules: no --mem; no set -u (breaks conda); log directory must already exist; LF line endings.
set -eo pipefail

PROJECT_ROOT=PROJECT_ROOT_CHANGEME            # CHANGEME: your own directory (holds configs, data, runs, logs)
CONFIG=CONFIG_FILE_CHANGEME                   # CHANGEME: absolute path of your yml (must set compile: False, run_dir inside PROJECT_ROOT)
EXPERIMENT=EXPERIMENT_NAME_CHANGEME           # CHANGEME: the experiment_name in that yml (run directories are <name>_<stamp>)
RUN_PARENT=RUN_PARENT_CHANGEME                # CHANGEME: the run_dir of that yml

mkdir -p "$PROJECT_ROOT/logs" "$RUN_PARENT"
source /data1/home/sunyiq/openhydronet_shared/env.sh
cd "$PROJECT_ROOT"

echo "host=$(hostname) start=$(date --iso-8601=seconds) job=$SLURM_JOB_ID config=$CONFIG"
python -u -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"

ohn train --config-file "$CONFIG"
RUN_DIR=$(ls -td "$RUN_PARENT"/${EXPERIMENT}_* | head -1)
echo "run_dir=$RUN_DIR"
ohn infer --run-dir "$RUN_DIR"
echo "done=$(date --iso-8601=seconds)"
