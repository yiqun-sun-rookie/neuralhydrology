"""Seal the frozen H04 signal-gate failure without starting training."""

from __future__ import annotations

import json
import os
import platform
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch

from hbv_history_conditioned_imm.parameter_switch import audit_parameter_signal
from hbv_history_conditioned_imm.scripts.run_h01_end_to_end_smoke import (
    _git_head,
    _sha256,
    _write_json,
    load_registry_row,
)
from hbv_history_conditioned_imm.scripts.run_h04_parameter_switch_capability import (
    DEFAULT_CONFIG_PATH,
    _generate_splits,
    _parameter_candidates,
    load_h04_config,
)


FAILURE_FILES = (
    "config_snapshot.json",
    "registry_entry.json",
    "signal_audit.json",
    "preflight_failure.json",
    "environment.json",
    "checksums.json",
)


def record_failure(*, project_root: str | Path) -> Path:
    root = Path(project_root).resolve()
    config = load_h04_config(DEFAULT_CONFIG_PATH)
    output = (root / str(config["result_relative_path"])).resolve()
    if output.exists():
        raise FileExistsError(f"H04 output already exists: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    registry_row = load_registry_row(str(config["experiment_id"]))
    if registry_row["status"] != "preflight_failed":
        raise ValueError("H04 registry is not marked preflight_failed")

    candidates = _parameter_candidates(config)
    training_batch, _, _ = _generate_splits(config, candidates)
    signal = audit_parameter_signal(
        training_batch,
        candidates,
        float(config["data"]["observation_standard_deviation"]),
        tuple(int(value) for value in config["forecast"]["leads_days"]),
    )
    observed = float(signal["minimum_pairwise_rmse_to_observation_sd_ratio"])
    threshold = float(
        config["capability_gates"][
            "minimum_pairwise_rmse_to_observation_sd_ratio"
        ]
    )
    if observed >= threshold:
        raise ValueError("H04 no longer reproduces its frozen signal failure")

    staging = Path(
        tempfile.mkdtemp(prefix=".h04-preflight-failure-", dir=output.parent)
    )
    try:
        _write_json(staging / "config_snapshot.json", config)
        _write_json(staging / "registry_entry.json", registry_row)
        _write_json(staging / "signal_audit.json", signal)
        _write_json(
            staging / "preflight_failure.json",
            {
                "experiment_id": config["experiment_id"],
                "stage": "filter_free_parameter_signal_gate",
                "observed_ratio": observed,
                "required_minimum_ratio": threshold,
                "passed": False,
                "training_started": False,
                "test_data_read": False,
                "checkpoint_created": False,
            },
        )
        _write_json(
            staging / "environment.json",
            {
                "python": sys.version,
                "platform": platform.platform(),
                "torch": torch.__version__,
                "numpy": np.__version__,
                "git_head": _git_head(root),
                "process_id": os.getpid(),
            },
        )
        checksums = {
            name: _sha256(staging / name)
            for name in FAILURE_FILES
            if name != "checksums.json"
        }
        _write_json(staging / "checksums.json", checksums)
        if {path.name for path in staging.iterdir()} != set(FAILURE_FILES):
            raise RuntimeError("H04 preflight failure artifact set is incomplete")
        staging.replace(output)
        return output
    except Exception:
        if staging.exists() and staging.parent == output.parent:
            shutil.rmtree(staging)
        raise


if __name__ == "__main__":
    print(record_failure(project_root=Path(__file__).resolve().parents[3]))
