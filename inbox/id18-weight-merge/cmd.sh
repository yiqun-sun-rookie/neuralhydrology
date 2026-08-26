#!/bin/bash
set -o pipefail

ROOT=/data1/home/sunyiq
REPO=${ROOT}/neuralhydrology
LANDING=${ROOT}/id18_weight_merge_20260826

echo "=== AUDIT IDENTITY ==="
date -Is
hostname
echo "user=${USER:-unknown}"

echo "=== RUNNER ==="
pgrep -af hpc_runner_active || true

echo "=== QUEUE SNAPSHOT ==="
sinfo -o '%.12P %.6a %.20l %.6D %.20N %.10T' || true
squeue -u "${USER:-sunyiq}" -o '%.18i %.22j %.10P %.8T %.10M %.20R' || true

echo "=== SHARED REPOSITORY READ-ONLY IDENTITY ==="
if [ -d "${REPO}/.git" ]; then
    (
        cd "${REPO}" || exit 1
        echo "branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
        echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
        echo "tracked_or_untracked_change_count=$(git status --porcelain 2>/dev/null | wc -l)"
        echo "remote=$(git config --get remote.origin.url 2>/dev/null || echo unknown)"
    )
else
    echo "REPOSITORY_MISSING=${REPO}"
fi

echo "=== EXACT E01 SOURCE CHECKPOINTS ==="
CHECKPOINTS=(
"${REPO}/runs/e01_loss/nse/E01_internal_holdout_nse_s100_2026_0731_2240_ep30/model_epoch030.pt"
"${REPO}/runs/e01_loss/nse/E01_internal_holdout_nse_s200_2026_0801_1739_ep30/model_epoch030.pt"
"${REPO}/runs/e01_loss/nse/E01_internal_holdout_nse_s300_2026_0801_1936_ep30/model_epoch030.pt"
"${REPO}/runs/e01_loss/flow_regime_nse/E01_internal_holdout_flow_regime_nse_s100_2026_0801_0937_ep30/model_epoch030.pt"
"${REPO}/runs/e01_loss/flow_regime_nse/E01_internal_holdout_flow_regime_nse_s200_2026_0801_1837_ep30/model_epoch030.pt"
"${REPO}/runs/e01_loss/flow_regime_nse/E01_internal_holdout_flow_regime_nse_s300_2026_0801_2106_ep30/model_epoch030.pt"
)
FOUND=0
for CKPT in "${CHECKPOINTS[@]}"; do
    if [ -f "${CKPT}" ]; then
        FOUND=$((FOUND + 1))
        sha256sum "${CKPT}"
        CFG=$(dirname "${CKPT}")/config.yml
        if [ -f "${CFG}" ]; then
            echo "CONFIG=${CFG}"
            grep -E '^(data_dir|train_start_date|train_end_date|validation_start_date|validation_end_date|test_start_date|test_end_date|loss|seed):' "${CFG}" || true
        else
            echo "CONFIG_MISSING=${CFG}"
        fi
    else
        echo "CHECKPOINT_MISSING=${CKPT}"
    fi
done
echo "checkpoint_count=${FOUND}/6"

echo "=== SHALLOW TASK DIRECTORY CANDIDATES ==="
find "${ROOT}" -maxdepth 2 -type d \( -iname '*id18*' -o -iname '*e01*' -o -iname '*holdout*' -o -iname '*post2000*' -o -iname '*safe*data*' \) -print 2>/dev/null | sort

echo "=== SAFE-DATA MANIFEST NAME CANDIDATES ==="
find "${ROOT}" -maxdepth 6 -type f \( -iname '*manifest*.json' -o -iname '*manifest*.sha256' -o -iname '*manifest*.sha256.json' \) -print 2>/dev/null \
    | grep -Ei 'id18|e01|holdout|post.?2000|safe|camels' \
    | sort || true

echo "=== LANDING DIRECTORY MUST BE ABSENT ==="
if [ -e "${LANDING}" ]; then
    echo "LANDING_ALREADY_EXISTS=${LANDING}"
else
    echo "LANDING_ABSENT=${LANDING}"
fi

echo "=== AUDIT COMPLETE: NO HYDROLOGICAL DATA FILE WAS OPENED ==="
exit 0
