#!/usr/bin/env bash
#SBATCH -J a64-database
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 02:00:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err

set -o pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export MKL_THREADING_LAYER=GNU

ROOT=/data1/home/sunyiq/autoresearch64
CAMELS=/data1/home/sunyiq/neuralhydrology/data/camels_us
cd "$ROOT" || exit 1
export PYTHONPATH="$ROOT/src:$PYTHONPATH"

echo "=== versions used for this build ==="
python -c "import numpy,pandas,pyarrow;print('numpy',numpy.__version__,'pandas',pandas.__version__,'pyarrow',pyarrow.__version__)"

echo "=== 1. build development source (64 basins) ==="
python src/unified_autoresearch/scripts/build_real_development_source.py \
  --camels-root "$CAMELS" \
  --selection src/unified_autoresearch/selection/development_basins_64_v1.json \
  --output-root runs/unified_autoresearch/development_source_real_64_hpc 2>&1 | tail -12

echo "=== 2. build both protocol packages ==="
python src/unified_autoresearch/scripts/build_real_development_packages.py \
  --source-root runs/unified_autoresearch/development_source_real_64_hpc \
  --selection src/unified_autoresearch/selection/development_basins_64_v1.json \
  --output-root runs/unified_autoresearch/development_packages_real_64_hpc 2>&1 | tail -6

echo "=== 3. independent per-basin verification ==="
python src/unified_autoresearch/scripts/verify_development_artifacts.py \
  --source-root runs/unified_autoresearch/development_source_real_64_hpc \
  --package-root runs/unified_autoresearch/development_packages_real_64_hpc \
  --camels-root "$CAMELS" \
  --selection src/unified_autoresearch/selection/development_basins_64_v1.json \
  --output runs/unified_autoresearch/VERIFICATION_64_HPC.json 2>&1 | tail -25

echo "=== 4. pre-search basin eligibility ==="
python src/unified_autoresearch/scripts/classify_development_basins.py \
  --package-root runs/unified_autoresearch/development_packages_real_64_hpc \
  --output runs/unified_autoresearch/BASIN_ELIGIBILITY_64_HPC.json 2>&1 | tail -22

echo "=== 5. do the Linux artifacts hash-match the Windows ones? ==="
cd runs/unified_autoresearch/development_source_real_64_hpc && sha256sum features.parquet targets.parquet static_attributes.json
echo "windows features.parquet 1c13a08328a588888c63bb7f44b6677d985e10121421583016a9d8774f414896"
echo "windows targets.parquet  3d070cd4a6f92e291ddf8844455be71b9d19da58e8a2d91824c4b503c2277573"
echo "windows statics.json     a59be77c9cf651112e616b525b215a15f0118527a5f843626538f511e9311734"
