#!/usr/bin/env bash
# Read-only paired interaction audit for the paper-facing nearest-neighbour result.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1/ladder_impact
TASKS="$ROOT/ladder_task_errors.csv"

echo "=== A. INPUT IDENTITY ==="
test -f "$TASKS" || { echo "MISSING_TASK_ERRORS"; exit 1; }
sha256sum "$TASKS"

echo "=== B. PAIRED INTERACTION DEFINITION ==="
echo "interaction = MAE(both nearest removed) - MAE(upstream removed) - MAE(downstream removed) + MAE(hidden target)"
echo "positive means the joint penalty is super-additive"

python - "$TASKS" <<'PY'
import sys
import pandas as pd

path = sys.argv[1]
frame = pd.read_csv(path)
keys = ["test_year", "target", "seed", "horizon_hours"]
pivot = frame.pivot(index=keys, columns="condition", values="mean_absolute_error_m")
nearest = {
    "zhenjiang": ("nanjing", "jiangyin"),
    "jiangyin": ("zhenjiang", "xuliujing"),
}
reported = {1, 3, 6, 12, 24}
rows = []
for key, row in pivot.iterrows():
    test_year, target, seed, horizon = key
    if int(horizon) not in reported:
        continue
    upstream, downstream = nearest[target]
    required = [
        "hidden_target",
        f"hidden_target_minus_{upstream}",
        f"hidden_target_minus_{downstream}",
        "hidden_target_both_nearest",
    ]
    if any(name not in row.index or pd.isna(row[name]) for name in required):
        raise RuntimeError(f"missing matched arm for {key}")
    interaction = (
        row["hidden_target_both_nearest"]
        - row[f"hidden_target_minus_{upstream}"]
        - row[f"hidden_target_minus_{downstream}"]
        + row["hidden_target"]
    )
    rows.append({
        "test_year": int(test_year),
        "target": target,
        "seed": int(seed),
        "horizon_hours": int(horizon),
        "interaction_m": float(interaction),
    })

paired = pd.DataFrame(rows)
expected = 2 * 5 * 8 * 10
if len(paired) != expected:
    raise RuntimeError(f"paired row count {len(paired)} != {expected}")
fold = (
    paired.groupby(["target", "horizon_hours", "test_year"], as_index=False)
    .agg(interaction_m=("interaction_m", "median"), seed_count=("seed", "nunique"))
)
summary = (
    fold.groupby(["target", "horizon_hours"], as_index=False)
    .agg(
        median_interaction_m=("interaction_m", "median"),
        minimum_interaction_m=("interaction_m", "min"),
        maximum_interaction_m=("interaction_m", "max"),
        positive_fold_years=("interaction_m", lambda s: int((s > 0).sum())),
        fold_count=("interaction_m", "size"),
    )
)
print("=== C. ACROSS-FOLD SUMMARY ===")
print(summary.to_csv(index=False), end="")
print("=== D. FOLD-LEVEL INTERACTIONS ===")
print(fold.to_csv(index=False), end="")
print("=== E. COUNTS ===")
print(f"paired_seed_rows={len(paired)} fold_rows={len(fold)}")
PY

echo "=== END ==="
