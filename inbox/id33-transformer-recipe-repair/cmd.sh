#!/bin/bash
# seq=33 read-only: fix the maxdepth bug, get gpu partitions, confirm torch
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
R33="$ROOT/results/33_transformer_recipe_repair"

echo "=== STAMP ==="; date -Iseconds

echo "=== A. RAW VALIDATION PREDICTIONS (correct depth) ==="
find "$R33" -mindepth 1 -maxdepth 6 -name 'validation_results.p' -printf '%10s  %p\n' 2>/dev/null | head -10 || true
echo "  count=$(find "$R33" -maxdepth 6 -name 'validation_results.p' 2>/dev/null | wc -l)"

echo "=== A2. WHAT IS ACTUALLY UNDER ONE ARM ==="
T2DIR=$(ls -1d "$R33"/T2/*/ 2>/dev/null | head -1)
echo "T2 run dir: $T2DIR"
ls -1 "$T2DIR" 2>&1 | head -15
echo "-- validation subtree --"
find "$T2DIR" -maxdepth 3 -type f -printf '%10s  %P\n' 2>/dev/null | head -20 || true

echo "=== B. GPU PARTITIONS ONLY ==="
sinfo -o "%.10P %.6a %.6D %.8t %.30N" 2>&1 | grep -E 'PARTITION|gpu' || true

echo "=== C. GPU NODES FREE RIGHT NOW ==="
sinfo -p hgpu2p,hgpu2 -N -o "%.10N %.10P %.8T %.8G" 2>&1 | head -20 || true

echo "=== D. TORCH + DETERMINISM CAPABILITY (import only) ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "$HOME/miniconda3/etc/profile.d/conda.sh" 2>/dev/null
conda activate nh_final 2>&1 | tail -1
python - <<'PY' 2>&1 | tail -8
import torch
print("torch", torch.__version__)
print("has use_deterministic_algorithms", hasattr(torch, "use_deterministic_algorithms"))
print("cudnn.deterministic default", torch.backends.cudnn.deterministic)
print("cudnn.benchmark default", torch.backends.cudnn.benchmark)
print("matmul.allow_tf32 default", torch.backends.cuda.matmul.allow_tf32)
print("cudnn.allow_tf32 default", torch.backends.cudnn.allow_tf32)
PY
