#!/usr/bin/env bash
#SBATCH -J id29_compare
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH -t 00:20:00
#SBATCH -o /data1/home/sunyiq/nearing2022_da/logs/compare_%j.out
#SBATCH -e /data1/home/sunyiq/nearing2022_da/logs/compare_%j.err

set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
export PYTHONPATH="$ROOT:${PYTHONPATH:-}"

SIM=$(ls -dt results/29_nearing2022_da_ar/nearing2022_simulation_seed0_*/ | head -1)
AR=$(ls -dt results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_*/ | head -1)
DA=$(ls -dt results/29_nearing2022_da_ar/assimilation_lead_1_holdout_0.0_from_*/ | head -1)

test -d "${SIM%/}/test" || { echo "SIM_TEST_MISSING"; exit 3; }
test -d "${AR%/}/test" || { echo "AR_TEST_MISSING"; exit 4; }
test -d "${DA%/}/test" || { echo "DA_TEST_MISSING"; exit 5; }

echo "SIM=${SIM%/}"
echo "AR=${AR%/}"
echo "DA=${DA%/}"

/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python \
    src/29_nearing2022_da_ar/scripts/compare_to_paper.py \
    --simulation "${SIM%/}" --autoregression "${AR%/}" --assimilation "${DA%/}" \
    --out results/29_nearing2022_da_ar/headline_table.csv

echo "=== FINAL TABLE ==="
cat results/29_nearing2022_da_ar/headline_table.csv
