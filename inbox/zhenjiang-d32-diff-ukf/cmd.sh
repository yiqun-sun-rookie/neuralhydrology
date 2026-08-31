#!/bin/bash
set -eo pipefail

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"

python - "${ROOT}" <<'PY'
from __future__ import annotations

import csv
import json
from pathlib import Path
import statistics
import sys

root = Path(sys.argv[1])
experiment_ids = (
    "ZHD32-DUKF-S17-V1",
    "ZHD32-DUKF-S29-V1",
    "ZHD32-DUKF-S43-V1",
)
summaries = []
for experiment_id in experiment_ids:
    attempt = root / "runs" / "formal" / experiment_id / "attempt_001"
    selection = json.loads(
        (attempt / "selection_validation_summary.json").read_text(encoding="utf-8")
    )
    data_identity = json.loads(
        (attempt / "data_identity.json").read_text(encoding="utf-8")
    )
    noise = json.loads(
        (attempt / "best_noise_parameters.json").read_text(encoding="utf-8")
    )
    with (attempt / "training_history.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        rows = list(csv.DictReader(handle))
    best_epoch = int(selection["best_epoch"])
    best_row = next(row for row in rows if int(row["epoch"]) == best_epoch)
    assimilation = float(best_row["validation_assimilation_mae_m"])
    open_loop = float(best_row["validation_open_loop_mae_m"])
    improvement_m = open_loop - assimilation
    counters = selection.get("test_target_counters")
    if counters != {
        "test_target_rows_read": 0,
        "test_target_values_loaded": 0,
        "test_target_values_parsed": 0,
    }:
        raise SystemExit("held-out target access counter changed")
    if data_identity.get("last_loaded_target_time_beijing", "") > (
        "2023-12-31T23:00:00+08:00"
    ):
        raise SystemExit("target boundary exceeds pre-2024 scope")
    summary = {
        "experiment_id": experiment_id,
        "completion_status": selection["status"],
        "best_epoch": best_epoch,
        "completed_epoch": int(selection["completed_epoch"]),
        "selected_validation_assimilation_mae_m": assimilation,
        "same_epoch_validation_open_loop_mae_m": open_loop,
        "assimilation_improvement_m": improvement_m,
        "assimilation_improvement_percent": (
            100.0 * improvement_m / open_loop
        ),
        "process_variance_count": len(noise["process_variances"]),
        "process_variance_min": min(noise["process_variances"]),
        "process_variance_max": max(noise["process_variances"]),
        "observation_variance_count": len(noise["observation_variances"]),
        "observation_variance_min": min(noise["observation_variances"]),
        "observation_variance_max": max(noise["observation_variances"]),
        "training_history_rows": len(rows),
        "artifact_names": sorted(path.name for path in attempt.iterdir() if path.is_file()),
        "last_loaded_target_time_beijing": data_identity[
            "last_loaded_target_time_beijing"
        ],
        "test_target_counters": counters,
    }
    summaries.append(summary)
    print("SEED_SUMMARY|" + json.dumps(summary, sort_keys=True))

assimilation_values = [
    row["selected_validation_assimilation_mae_m"] for row in summaries
]
open_loop_values = [row["same_epoch_validation_open_loop_mae_m"] for row in summaries]
improvements = [row["assimilation_improvement_m"] for row in summaries]
aggregate = {
    "seed_count": len(summaries),
    "assimilation_mae_mean_m": statistics.mean(assimilation_values),
    "assimilation_mae_sample_standard_deviation_m": statistics.stdev(
        assimilation_values
    ),
    "assimilation_mae_min_m": min(assimilation_values),
    "assimilation_mae_max_m": max(assimilation_values),
    "open_loop_mae_mean_m": statistics.mean(open_loop_values),
    "paired_improvement_mean_m": statistics.mean(improvements),
    "paired_improvement_sample_standard_deviation_m": statistics.stdev(
        improvements
    ),
    "paired_improvement_all_positive": all(value > 0.0 for value in improvements),
}
print("AGGREGATE_SUMMARY|" + json.dumps(aggregate, sort_keys=True))
PY
