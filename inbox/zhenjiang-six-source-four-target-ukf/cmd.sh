#!/usr/bin/env bash
set -eo pipefail
date --iso-8601=seconds
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import hashlib
import json
import math
from pathlib import Path

root = Path("/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001")
assert root.is_dir() and not root.is_symlink()
for seed in (17, 29, 43):
    run = root / "runs" / "stage_a" / ("seed_" + str(seed))
    assert run.is_dir() and not run.is_symlink()
    def raw_file(name):
        path = run / name
        assert path.is_file() and not path.is_symlink()
        assert path.resolve().parent == run.resolve()
        return path.read_bytes()
    manifest_raw = raw_file("completion_manifest.json")
    manifest = json.loads(manifest_raw)
    receipt = json.loads(raw_file("formal_run_receipt.json"))
    history = json.loads(raw_file("training_history.json"))
    execution = json.loads(raw_file("hpc_execution_receipt.json"))
    assert manifest["status"] == "complete" and manifest["seed"] == seed
    assert manifest["training_years"] == [2017, 2018, 2019, 2020, 2021]
    assert manifest["selection_year"] == 2022
    assert manifest["selection_use"] == "best_epoch_selection_only"
    manifest_sha = hashlib.sha256(manifest_raw).hexdigest()
    assert receipt["training_completion_manifest_sha256"] == manifest_sha
    assert set(manifest["files"]) == {"best_checkpoint.pt", "last_checkpoint.pt", "training_history.json", "environment_manifest.json"}
    identities = {}
    for name, expected in manifest["files"].items():
        raw = raw_file(name)
        sha = hashlib.sha256(raw).hexdigest()
        assert len(raw) == expected["byte_count"] and sha == expected["sha256"], name
        identities[name] = {"byte_count": len(raw), "sha256": sha}
    best = float("inf")
    best_epoch = None
    no_improvement = 0
    threshold = manifest["training_configuration"]["minimum_improvement_m"]
    assert threshold == 0.0001
    for index, row in enumerate(history, 1):
        assert row["epoch"] == index
        value = row["selection_2022_mean_absolute_error_m"]
        assert math.isfinite(value) and value >= 0
        improved = value <= best - threshold
        assert row["selected_as_best"] == improved
        if improved:
            best = value
            best_epoch = index
            no_improvement = 0
        else:
            no_improvement += 1
    assert manifest["best_epoch"] == best_epoch
    assert manifest["best_selection_mean_absolute_error_m"] == best
    metrics = manifest["best_selection_metrics"]
    assert metrics["overall_mean_absolute_error_m"] == best
    assert metrics["target_stations"] == ["nanjing", "zhenjiang", "jiangyin", "xuliujing", "wusongkou"]
    assert metrics["lead_hours_after_analysis"] == list(range(24))
    cells = metrics["per_lead_target_mean_absolute_error_m"]
    assert len(cells) == 24 and all(len(row) == 5 for row in cells)
    assert all(math.isfinite(x) and x >= 0 for row in cells for x in row)
    assert abs(sum(sum(row) for row in cells) / 120 - best) < 1e-12
    for station in range(5):
        assert abs(sum(row[station] for row in cells) / 24 - metrics["per_target_mean_absolute_error_m"][station]) < 1e-12
    output = {
        "seed": seed,
        "status": "saved_artifact_identity_and_selection_consistency_passed",
        "completion_manifest_sha256": manifest_sha,
        "artifact_identities": identities,
        "training_configuration": manifest["training_configuration"],
        "epochs_completed": len(history),
        "best_epoch": best_epoch,
        "best_selection_mean_absolute_error_m": best,
        "final_no_improvement_epochs": no_improvement,
        "best_selection_metrics": metrics,
        "training_history": history,
        "hpc_execution_receipt": execution,
        "raw_training_or_target_data_opened": False,
        "checkpoint_deserialized": False,
    }
    print("SEED_RESULT_JSON=" + json.dumps(output, sort_keys=True))
print("read_only_saved_artifact_query=true new_experiments=0 sbatch_calls=0 raw_data_reads=0")
PY
