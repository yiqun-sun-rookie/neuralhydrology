from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path


HERE = Path(__file__).resolve().parent
RUNS = HERE / "runs" / "formal_gpu"
LOCAL_CONTROL_NSE = 0.9599600380703273


def read_metrics() -> tuple[Path, dict]:
    path = RUNS / "idx0000_lr0p01_hs32_nl1_mult10" / "metrics.json"
    metrics = json.loads(path.read_text(encoding="utf-8"))
    if metrics.get("status") != "ok":
        raise RuntimeError(f"Run is not complete: {path}")
    return path, metrics


control_path, control = read_metrics()
control_nse = float(control["nse"])

summary = {
    "experiment_family": "WRR-HLRB-HPCBRIDGE-20260901",
    "created_at": datetime.now().isoformat(timespec="seconds"),
    "slurm_job_id": os.environ.get("SLURM_JOB_ID"),
    "comparison_contract": "Repeat the locally completed learning-rate 0.01 once on HPC using the same training and validation contract",
    "local_common_control": {
        "learning_rate": 0.01,
        "validation_nse": LOCAL_CONTROL_NSE,
    },
    "hpc_common_control": {
        "learning_rate": 0.01,
        "validation_nse": control_nse,
        "metrics_path": str(control_path),
    },
    "hpc_control_minus_local_control_nse": control_nse - LOCAL_CONTROL_NSE,
    "absolute_anchor_gap_nse": abs(control_nse - LOCAL_CONTROL_NSE),
    "held_out_test_loaded": False,
    "interpretation_limit": "One common control is a practical environment check; it does not prove universal equivalence between GPU types or replace the local hyperparameter batch.",
}

output = HERE / "bridge_summary.json"
output.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print(json.dumps(summary, indent=2))
