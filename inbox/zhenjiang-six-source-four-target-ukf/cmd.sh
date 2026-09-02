#!/bin/bash
set -o pipefail

ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2"

printf '=== SNAPSHOT_TIME ===\n'
date -Is

printf '=== FILTER_ARTIFACTS ===\n'
find "${ROOT}/runs" -maxdepth 6 -name 'best_filter_checkpoint.pt' -type f -printf '%s|%p\n' 2>/dev/null | sort -t'|' -k2 || true

printf '=== TRAINING_SUMMARY ===\n'
find "${ROOT}/runs" -maxdepth 6 -name 'summary.json' -type f 2>/dev/null | grep filter | sort | while read -r f; do
  printf 'SUMMARY|%s\n' "$f"; cat "$f" 2>/dev/null; printf '\n'
done || true

printf '=== TRAINING_HISTORY ===\n'
find "${ROOT}/runs" -maxdepth 6 -name 'training_history.json' -type f 2>/dev/null | sort | while read -r f; do
  printf 'HISTORY|%s\n' "$f"; cat "$f" 2>/dev/null; printf '\n'
done || true

printf '=== GRADIENT_ZERO_SUMMARY ===\n'
python - "${ROOT}" <<'PY' 2>&1 || true
import json, glob, sys
root = sys.argv[1]
for path in sorted(glob.glob(root + "/runs/**/gradient_history.json", recursive=True)):
    try:
        rows = json.load(open(path)).get("batches", [])
    except Exception as error:
        print("FILE|%s|READ_ERROR|%s" % (path, error)); continue
    if not rows:
        continue
    by = {}
    for row in rows:
        by.setdefault(row.get("epoch"), []).append(int(row.get("zero_gradient_count", 0)))
    print("FILE|%s|batch_rows=%d" % (path, len(rows)))
    for epoch in sorted(by, key=lambda v: (v is None, v)):
        values = by[epoch]
        print("  epoch=%s batches=%d zero_grad_of_38 min=%d max=%d mean=%.2f"
              % (epoch, len(values), min(values), max(values), sum(values) / len(values)))
PY

printf '=== LEARNED_Q_AND_R ===\n'
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "${HOME}/miniconda3/etc/profile.d/conda.sh" 2>/dev/null || true
conda activate nh_final 2>/dev/null || true
timeout 420 python - "${ROOT}" <<'PY' 2>&1 || true
import glob, math, sys
import torch
import torch.nn.functional as F

FLOOR = 1e-4
root = sys.argv[1]
paths = sorted(glob.glob(root + "/runs/**/best_filter_checkpoint.pt", recursive=True))
print("checkpoint_count=%d torch=%s" % (len(paths), torch.__version__))
for path in paths:
    checkpoint = torch.load(path, map_location="cpu")
    state = checkpoint.get("filter_state_dict", {})
    print("FILE|%s" % path)
    print("  seed=%s epoch=%s selection_mae_m=%s"
          % (checkpoint.get("seed"), checkpoint.get("epoch"),
             checkpoint.get("selection_mae_m")))
    for name, key, initial_variance in (
        ("Q", "process_noise.raw_standard_deviation", 0.001),
        ("R", "observation_noise.raw_standard_deviation", 0.01),
    ):
        raw = state.get(key)
        if raw is None:
            print("  %s=MISSING" % name)
            continue
        deviation = (FLOOR + F.softplus(raw.double())).tolist()
        initial = math.sqrt(initial_variance)
        ratio = [value / initial for value in deviation]
        print("  %s_dim=%d initial_sd=%.6f" % (name, len(deviation), initial))
        print("  %s_sd=%s" % (name, ", ".join("%.6f" % v for v in deviation)))
        print("  %s_sd_over_initial min=%.4f max=%.4f mean=%.4f"
              % (name, min(ratio), max(ratio), sum(ratio) / len(ratio)))
        print("  %s_at_variance_floor_count=%d"
              % (name, sum(1 for v in deviation if v <= FLOOR * 1.01)))
PY

printf '=== ORIGINAL_R2_SAFETY ===\n'
for specification in \
  "704366cb22eef1d3acb58f4f0524a6e50d49ffa442afcf0fca498fbd21154cb8|${ROOT}/run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json" \
  "badf3ee5f8cf3f0d9c5e5771b11385a45a6f22d6355fc43357bc44f2bd364c9e|${ROOT}/evidence/development_2023/evaluation/attempt_001.partial/development_access_started.json" \
  "f64e5ffcc47061d97f66e28e15ec45f7412b1d8a59455771180c4ef47eab9281|${ROOT}/run/scripts/analysis/zhenjiang_six_source_four_target_d32_gru_ukf_development_evaluation_v1.py"
do
  expected="${specification%%|*}"
  path="${specification#*|}"
  observed="$(sha256sum "${path}" 2>/dev/null | awk '{print $1}')"
  printf 'ORIGINAL_IDENTITY|match=%s|path=%s\n' "$([ "${observed}" = "${expected}" ] && echo true || echo false)" "${path}"
done
echo 'HELD_OUT_2024_TARGET_ACCESS_AUTHORIZED=false'
echo 'BOUNDARY_FUTURE_TARGET_ACCESS_AUTHORIZED=false'
printf '=== SNAPSHOT_END ===\n'
date -Is
exit 0
