#!/bin/bash
# Re-run all 9 variants of hbv_lite_cma_repro_v01 with the patched runner
# (which now persists per-basin p_* parameters AND state_* final states).
#
# CMA-ES seeds are deterministic (42 + restart*1000), so NSE numbers should
# reproduce the original 0.6227 ensemble exactly, just with added columns.
#
# Total wall time: ~9h on i9-13900K with 6 workers per variant.

set -e
cd "$(dirname "$0")/../../.."

BASE="results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01"
LOG="logs/10_global_conceptual_model_benchmark/rerun_9variants_$(date +%Y%m%d_%H%M%S).log"
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
    echo "[$(date +%H:%M:%S)] STARTING $name" | tee -a "$LOG"
    echo "  bounds=$bounds pet=$pet init=($init_mean,$init_sigma) loss=$loss kge_w=$kge_w" | tee -a "$LOG"
    echo "  outdir=$outdir" | tee -a "$LOG"
    echo "===================================================================" | tee -a "$LOG"

    HBV_BOUNDS=$bounds python -X utf8 -m src.scl_hydro.scripts.run_hbv_lite_cma_repro_v01 \
        --workers 6 --no-skip-existing \
        --forcing maurer --pet-method "$pet" \
        --init-mean "$init_mean" --init-sigma "$init_sigma" \
        --loss "$loss" --kge-weight "$kge_w" \
        --output-root "$outdir" 2>&1 | tee -a "$LOG"

    echo "[$(date +%H:%M:%S)] FINISHED $name" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
}

# v1: Oudin tight bounds, init=0.5, NSE
run_variant v1 v1 oudin 0.5 0.3 nse 0.5 "${BASE}"

# v5: Oudin wider bounds, init=0.5, NSE
run_variant v5 v5 oudin 0.5 0.3 nse 0.5 "${BASE}_BEST"

# v6: PT wider bounds, init=0.5, NSE
run_variant v6 v5 priestley_taylor 0.5 0.3 nse 0.5 "${BASE}_v6_PT"

# v7: PT tight bounds, init=0.5, NSE
run_variant v7 v1 priestley_taylor 0.5 0.3 nse 0.5 "${BASE}_v7_PT_tight"

# v8: PT tight bounds, init=0.3
run_variant v8 v1 priestley_taylor 0.3 0.3 nse 0.5 "${BASE}_v8_PT_tight_init03"

# v9: PT tight bounds, init=0.7
run_variant v9 v1 priestley_taylor 0.7 0.3 nse 0.5 "${BASE}_v9_PT_tight_init07"

# v10: PT tight bounds, init=0.9
run_variant v10 v1 priestley_taylor 0.9 0.3 nse 0.5 "${BASE}_v10_PT_tight_init09"

# v11: PT tight bounds, KGE hybrid w=0.1
run_variant v11 v1 priestley_taylor 0.5 0.3 hybrid 0.1 "${BASE}_v11_PT_KGE01"

# v12: PT tight bounds, sigma=0.5
run_variant v12 v1 priestley_taylor 0.5 0.5 nse 0.5 "${BASE}_v12_PT_sigma05"

echo "" | tee -a "$LOG"
echo "===================================================================" | tee -a "$LOG"
echo "[$(date +%H:%M:%S)] ALL 9 VARIANTS COMPLETED" | tee -a "$LOG"
echo "===================================================================" | tee -a "$LOG"
