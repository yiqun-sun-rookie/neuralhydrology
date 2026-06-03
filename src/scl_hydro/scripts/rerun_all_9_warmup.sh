#!/bin/bash
# Re-run all 9 variants with --warmup-year (Kratzert-style 1988-89 warmup
# before eval period 1989-10-01 .. 1999-09-30).
#
# Outputs to new directories with _warmup suffix to preserve the original
# (cal_final_state as eval init) ensemble for direct comparison.
#
# Expected: median NSE shift +0.005 .. +0.015 (eval period sees correct
# 1989-10-01 init state instead of time-reversed 2008-09-30 state, removing
# SLZ mismatch bias in slow-baseflow basins).
#
# Total wall time: ~9-10h on 6 workers per variant.

set -e
cd "$(dirname "$0")/../../.."

BASE="results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01"
LOG="logs/10_global_conceptual_model_benchmark/rerun_9variants_warmup_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG")"

run_variant() {
    local name="$1"
    local bounds="$2"
    local pet="$3"
    local init_mean="$4"
    local init_sigma="$5"
    local loss="$6"
    local kge_w="$7"
    local outdir="$8"

    echo "===================================================================" | tee -a "$LOG"
    echo "[$(date +%H:%M:%S)] STARTING $name (with --warmup-year)" | tee -a "$LOG"
    echo "  bounds=$bounds pet=$pet init=($init_mean,$init_sigma) loss=$loss kge_w=$kge_w" | tee -a "$LOG"
    echo "  outdir=$outdir" | tee -a "$LOG"
    echo "===================================================================" | tee -a "$LOG"

    HBV_BOUNDS=$bounds python -X utf8 -m src.scl_hydro.scripts.run_hbv_lite_cma_repro_v01 \
        --workers 6 --no-skip-existing --warmup-year \
        --forcing maurer --pet-method "$pet" \
        --init-mean "$init_mean" --init-sigma "$init_sigma" \
        --loss "$loss" --kge-weight "$kge_w" \
        --output-root "$outdir" 2>&1 | tee -a "$LOG"

    echo "[$(date +%H:%M:%S)] FINISHED $name" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
}

run_variant v1  v1 oudin            0.5 0.3 nse    0.5 "${BASE}_warmup"
run_variant v5  v5 oudin            0.5 0.3 nse    0.5 "${BASE}_BEST_warmup"
run_variant v6  v5 priestley_taylor 0.5 0.3 nse    0.5 "${BASE}_v6_PT_warmup"
run_variant v7  v1 priestley_taylor 0.5 0.3 nse    0.5 "${BASE}_v7_PT_tight_warmup"
run_variant v8  v1 priestley_taylor 0.3 0.3 nse    0.5 "${BASE}_v8_PT_tight_init03_warmup"
run_variant v9  v1 priestley_taylor 0.7 0.3 nse    0.5 "${BASE}_v9_PT_tight_init07_warmup"
run_variant v10 v1 priestley_taylor 0.9 0.3 nse    0.5 "${BASE}_v10_PT_tight_init09_warmup"
run_variant v11 v1 priestley_taylor 0.5 0.3 hybrid 0.1 "${BASE}_v11_PT_KGE01_warmup"
run_variant v12 v1 priestley_taylor 0.5 0.5 nse    0.5 "${BASE}_v12_PT_sigma05_warmup"

echo "" | tee -a "$LOG"
echo "===================================================================" | tee -a "$LOG"
echo "[$(date +%H:%M:%S)] ALL 9 WARMUP VARIANTS COMPLETED" | tee -a "$LOG"
echo "===================================================================" | tee -a "$LOG"
