#!/usr/bin/env bash
# =============================================================================
# Smoke test for the repro_v01 benchmark-aligned protocol.
#
# 6 basins (2 snow + 2 humid + 2 semi-arid), 3 models, lower trial count
# than full production. Validates that the protocol switch, two-segment
# splits, and Superflex n_restarts plumbing all work end-to-end before
# committing HPC time to the full 531-basin rerun.
#
# Output dir: results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_smoke/
#
# Usage:
#   sbatch src/xaj_global_pilot/hpc/smoke_test_repro.slurm
# =============================================================================
#SBATCH -J xaj-smoke-repro
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 00:30:00
#SBATCH -o logs/10_global_conceptual_model_benchmark/smoke_repro-%j.out
#SBATCH -e logs/10_global_conceptual_model_benchmark/smoke_repro-%j.err

set -eo pipefail

# --- 环境 ---
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate "${CONDA_ENV:-nh_final}" || { echo "[FATAL] conda activate failed"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

# --- 参数 ---
IDEA="10_global_conceptual_model_benchmark"
PROTOCOL="repro_v01"
OUTPUT_DIR="results/${IDEA}/camels_us_531_repro_v01_smoke"
CHUNK_FILE="src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro_smoke.txt"
DATA_ROOT="data/camels_us"
TRIALS=200       # 远低于全量 5000，仅用于验证 plumbing
RESTARTS=2       # 显式给 Superflex 也能多重启

mkdir -p "logs/${IDEA}" "${OUTPUT_DIR}"

# --- Pre-flight ---
echo "=========================================="
echo "[$(date)] XAJ Global Pilot — Repro Smoke"
echo "=========================================="
echo "[INFO] Job: $SLURM_JOB_ID, Node: $(hostname)"
echo "[INFO] Python: $(python --version 2>&1)"
echo "[INFO] Protocol: ${PROTOCOL}"
echo "[INFO] Trials: ${TRIALS}, Restarts: ${RESTARTS}, Data: ${DATA_ROOT}"
echo "[INFO] (Forcing is derived from --protocol; repro_v01 expects maurer_extended)"

[ -d "$DATA_ROOT" ]   || { echo "[FATAL] Data not found: $DATA_ROOT";   exit 1; }
[ -d "${DATA_ROOT}/basin_mean_forcing/maurer_extended" ] \
    || { echo "[FATAL] Forcing dir missing: ${DATA_ROOT}/basin_mean_forcing/maurer_extended/ — populate before sbatch"; exit 1; }
[ -f "$CHUNK_FILE" ]  || { echo "[FATAL] Smoke chunk not found: $CHUNK_FILE"; exit 1; }

python -c "from src.xaj_global_pilot.runner import run_single_model_basin; print('[INFO] Import OK')" \
    || { echo "[FATAL] Import failed"; exit 1; }

echo ""
echo "[INFO] Smoke chunk: $CHUNK_FILE"
echo "[INFO] Basins: $(cat $CHUNK_FILE | tr '\n' ' ')"

# --- 三模型 ---
for MODEL in xaj_pdd hbv gr4j_pdd; do
    echo ""
    echo "[$(date)] --- Running ${MODEL} (${PROTOCOL}) ---"
    python -u -m src.xaj_global_pilot.hpc.run_conceptual_benchmark_chunk \
        --model ${MODEL} \
        --chunk-file ${CHUNK_FILE} \
        --protocol ${PROTOCOL} \
        --output-dir ${OUTPUT_DIR} \
        --data-root ${DATA_ROOT} \
        --trials ${TRIALS} \
        --restarts ${RESTARTS}
    echo "[$(date)] ${MODEL} done (exit: $?)"
done

# --- Verify metadata captured what we expected ---
echo ""
echo "[$(date)] --- Verifying metadata ---"
for META in ${OUTPUT_DIR}/summary/*.metadata.json; do
    echo ""
    echo "[INFO] ${META}"
    python -c "
import json, sys
m = json.load(open('${META}'))
required = ['protocol', 'protocol_version', 'forcing',
            'calibration_start', 'calibration_end',
            'evaluation_start', 'evaluation_end',
            'trials', 'restarts']
missing = [k for k in required if k not in m]
if missing:
    sys.exit(f'[FAIL] Missing metadata keys: {missing}')
if m['protocol'] != '${PROTOCOL}':
    sys.exit(f'[FAIL] protocol mismatch: {m[\"protocol\"]}')
if m['restarts'] != ${RESTARTS}:
    sys.exit(f'[FAIL] restarts mismatch: {m[\"restarts\"]}')
if m['forcing'] != 'maurer_extended':
    sys.exit(f'[FAIL] forcing mismatch (expected maurer_extended for repro_v01): {m[\"forcing\"]}')
if (m['calibration_start'], m['calibration_end']) != ('1999-10-01', '2008-09-30'):
    sys.exit(f'[FAIL] calibration window: {m[\"calibration_start\"]}..{m[\"calibration_end\"]}')
if (m['evaluation_start'], m['evaluation_end']) != ('1989-10-01', '1999-09-30'):
    sys.exit(f'[FAIL] evaluation window: {m[\"evaluation_start\"]}..{m[\"evaluation_end\"]}')
print(f'[OK] protocol={m[\"protocol\"]} forcing={m[\"forcing\"]} '
      f'cal={m[\"calibration_start\"]}..{m[\"calibration_end\"]} '
      f'eval={m[\"evaluation_start\"]}..{m[\"evaluation_end\"]} trials={m[\"trials\"]} restarts={m[\"restarts\"]}')
" || exit 1
done

echo ""
echo "=========================================="
echo "[DONE] Repro smoke complete."
echo "[INFO] Results: ${OUTPUT_DIR}/summary/"
echo "[INFO] If metadata verification passed for all 3 models, the"
echo "       protocol switch + n_restarts plumbing is wired correctly."
echo "       Next step: full-protocol 531 rerun (a separate SLURM)."
echo "=========================================="
