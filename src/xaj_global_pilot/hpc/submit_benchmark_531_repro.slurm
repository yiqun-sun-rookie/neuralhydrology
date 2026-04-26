#!/usr/bin/env bash
# =============================================================================
# Full 531-basin run under the repro_v01 benchmark-aligned protocol.
#
# Array job: 33 tasks = 11 chunks x 3 models
#   task 0-10:  xaj_pdd   chunk_001..011
#   task 11-21: hbv       chunk_001..011
#   task 22-32: gr4j_pdd  chunk_001..011
#
# 9-WY calibration (1999-2008) + 10-WY evaluation (1989-1999), maurer_extended
# forcing, n_trials=5000, n_restarts=3 uniform across models. Each task ~50
# basins; expect ~12-14 h per task with HBV the slowest.
#
# Pre-flight requires:
#   data/camels_us/basin_mean_forcing/maurer_extended/  (CAMELS-US 531 set)
#
# Pre-flight will auto-build the per-protocol chunks dir if it is missing.
#
# Usage:
#   sbatch src/xaj_global_pilot/hpc/submit_benchmark_531_repro.slurm
#
# Partial rerun (only task 5 and task 18):
#   sbatch --array=5,18 src/xaj_global_pilot/hpc/submit_benchmark_531_repro.slurm
# =============================================================================
#SBATCH -J xaj-bench-repro
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 24:00:00
#SBATCH --array=0-32
#SBATCH -o logs/10_global_conceptual_model_benchmark/repro_%a-%j.out
#SBATCH -e logs/10_global_conceptual_model_benchmark/repro_%a-%j.err

set -eo pipefail

# --- 环境 ---
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate "${CONDA_ENV:-nh_final}" || { echo "[FATAL] conda activate failed"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

# --- 协议参数 (LOCKED, do not edit casually) ---
IDEA="10_global_conceptual_model_benchmark"
PROTOCOL="repro_v01"
PROTOCOL_VERSION="camels_us_531_repro_v01"
OUTPUT_DIR="results/${IDEA}/${PROTOCOL_VERSION}"
CHUNK_DIR="${OUTPUT_DIR}/chunks"
DATA_ROOT="data/camels_us"
FORCING_SUBDIR="maurer_extended"
MANIFEST="src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt"
TRIALS=5000
RESTARTS=3
N_CHUNKS=11

mkdir -p "logs/${IDEA}" "${OUTPUT_DIR}"

# --- Array task -> model + chunk ---
MODELS=(xaj_pdd hbv gr4j_pdd)
MODEL_IDX=$((SLURM_ARRAY_TASK_ID / N_CHUNKS))
CHUNK_IDX=$((SLURM_ARRAY_TASK_ID % N_CHUNKS + 1))
MODEL=${MODELS[$MODEL_IDX]}
CHUNK_FILE="${CHUNK_DIR}/chunk_$(printf '%03d' ${CHUNK_IDX}).txt"

# --- Pre-flight ---
echo "=========================================="
echo "[$(date)] XAJ Repro Benchmark — Task ${SLURM_ARRAY_TASK_ID}/32"
echo "=========================================="
echo "[INFO] Job: $SLURM_JOB_ID, Node: $(hostname)"
echo "[INFO] Protocol: ${PROTOCOL} (${PROTOCOL_VERSION})"
echo "[INFO] Model: ${MODEL}, Chunk: ${CHUNK_IDX}/${N_CHUNKS}"
echo "[INFO] Forcing: ${FORCING_SUBDIR} (auto-derived from --protocol)"
echo "[INFO] Trials: ${TRIALS}, Restarts: ${RESTARTS}"
echo "[INFO] Python: $(python --version 2>&1)"

# Verify forcing data is present (this is the #1 source of silent failures).
[ -d "${DATA_ROOT}/basin_mean_forcing/${FORCING_SUBDIR}" ] \
    || { echo "[FATAL] Forcing dir missing: ${DATA_ROOT}/basin_mean_forcing/${FORCING_SUBDIR}/ — populate maurer_extended before sbatch"; exit 1; }
[ -f "$MANIFEST" ] \
    || { echo "[FATAL] Manifest missing: $MANIFEST"; exit 1; }

# Build chunks if missing (only the first task that wins the race actually
# writes; later tasks find the files already there). Use the repro manifest
# explicitly so chunks are independent of v02's chunk dir.
if [ ! -f "$CHUNK_FILE" ]; then
    echo "[INFO] Chunk dir incomplete; building chunks under ${CHUNK_DIR}"
    python -u -m src.xaj_global_pilot.hpc.build_conceptual_benchmark_chunks \
        --manifest "${MANIFEST}" \
        --output-dir "${OUTPUT_DIR}" \
        --allow-scale-up
fi

[ -f "$CHUNK_FILE" ] \
    || { echo "[FATAL] Chunk file still missing after build: $CHUNK_FILE"; exit 1; }

python -c "from src.xaj_global_pilot.runner import run_single_model_basin; print('[INFO] Import OK')" \
    || { echo "[FATAL] Import failed"; exit 1; }

echo "[INFO] Basins in chunk: $(wc -l < ${CHUNK_FILE})"

# --- 运行 ---
echo ""
echo "[$(date)] Starting ${MODEL} on chunk_$(printf '%03d' ${CHUNK_IDX}) ..."

python -u -m src.xaj_global_pilot.hpc.run_conceptual_benchmark_chunk \
    --model ${MODEL} \
    --chunk-file ${CHUNK_FILE} \
    --protocol ${PROTOCOL} \
    --output-dir ${OUTPUT_DIR} \
    --data-root ${DATA_ROOT} \
    --trials ${TRIALS} \
    --restarts ${RESTARTS} \
    --skip-existing

EXIT_CODE=$?

# --- Spot-check that this task wrote the protocol-aligned metadata ---
META_FILE="${OUTPUT_DIR}/summary/${MODEL}_chunk_$(printf '%03d' ${CHUNK_IDX}).metadata.json"
if [ -f "${META_FILE}" ]; then
    python -c "
import json, sys
m = json.load(open('${META_FILE}'))
checks = [
    ('protocol', '${PROTOCOL}'),
    ('forcing', '${FORCING_SUBDIR}'),
    ('calibration_start', '1999-10-01'),
    ('calibration_end',   '2008-09-30'),
    ('evaluation_start',  '1989-10-01'),
    ('evaluation_end',    '1999-09-30'),
]
for k, expected in checks:
    if m.get(k) != expected:
        sys.exit(f'[FAIL] metadata {k}={m.get(k)!r}, expected {expected!r}')
print(f'[OK] metadata sanity check passed for {m[\"model\"]} chunk={m[\"chunk_file\"]}')"
fi

echo ""
echo "=========================================="
echo "[$(date)] Done: ${MODEL} chunk_$(printf '%03d' ${CHUNK_IDX}) (exit: ${EXIT_CODE})"
echo "=========================================="
exit ${EXIT_CODE}
