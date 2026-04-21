from __future__ import annotations

from pathlib import Path
import sys

import numpy as np
import pandas as pd
import xarray as xr


SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "src" / "namou_kuwei" / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import build_mtslstm_daily_branch_data  # noqa: E402
import run_experiment  # noqa: E402


class _Completed:
    def __init__(self, returncode: int = 0, stdout: str = "", stderr: str = ""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def test_find_metrics_file_prefers_latest_epoch(tmp_path: Path):
    run_dir = tmp_path / "run_x"
    p5 = run_dir / "test" / "model_epoch005" / "test_metrics.csv"
    p60 = run_dir / "test" / "model_epoch060" / "test_metrics.csv"
    p5.parent.mkdir(parents=True, exist_ok=True)
    p60.parent.mkdir(parents=True, exist_ok=True)
    p5.write_text("NSE\n0.1\n", encoding="utf-8")
    p60.write_text("NSE\n0.2\n", encoding="utf-8")

    selected = run_experiment._find_metrics_file(run_dir)
    assert selected == p60


def test_run_train_maps_cpu_device_to_gpu_flag(monkeypatch):
    calls = []

    def fake_run(cmd, *args, **kwargs):  # noqa: ANN001
        calls.append(cmd)
        return _Completed(returncode=0)

    monkeypatch.setattr(run_experiment.subprocess, "run", fake_run)
    monkeypatch.setattr(
        run_experiment,
        "_check_runtime_capacity",
        lambda *args, **kwargs: (True, "ok"),  # noqa: ARG005
        raising=False,
    )

    ok = run_experiment.run_train("dummy_config.yml", device="cpu")
    assert ok is True
    assert len(calls) == 2
    train_cmd = calls[1]
    assert "--gpu" in train_cmd
    assert "-1" in train_cmd
    assert "--device" not in train_cmd


def test_run_train_maps_cuda_device_to_gpu_flag(monkeypatch):
    calls = []

    def fake_run(cmd, *args, **kwargs):  # noqa: ANN001
        calls.append(cmd)
        return _Completed(returncode=0)

    monkeypatch.setattr(run_experiment.subprocess, "run", fake_run)
    monkeypatch.setattr(
        run_experiment,
        "_check_runtime_capacity",
        lambda *args, **kwargs: (True, "ok"),  # noqa: ARG005
        raising=False,
    )

    ok = run_experiment.run_train("dummy_config.yml", device="cuda:0")
    assert ok is True
    assert len(calls) == 2
    train_cmd = calls[1]
    assert "--gpu" in train_cmd
    assert "0" in train_cmd
    assert "--device" not in train_cmd


def test_run_train_skips_training_when_runtime_capacity_is_insufficient(monkeypatch):
    calls = []

    def fake_run(cmd, *args, **kwargs):  # noqa: ANN001
        calls.append(cmd)
        return _Completed(returncode=0)

    monkeypatch.setattr(run_experiment.subprocess, "run", fake_run)
    monkeypatch.setattr(
        run_experiment,
        "_check_runtime_capacity",
        lambda *args, **kwargs: (False, "insufficient resources"),  # noqa: ARG005
        raising=False,
    )

    ok = run_experiment.run_train("dummy_config.yml", device="cuda:0")
    assert ok is False
    assert len(calls) == 1


def test_add_previous_day_sum_features_repeats_previous_day_total_per_hour():
    index = pd.date_range("2020-01-01 00:00:00", periods=72, freq="h")
    df = pd.DataFrame({
        "p_aka": np.ones(len(index), dtype=float),
        "p_bandang": np.arange(len(index), dtype=float),
    }, index=index)

    enriched = build_mtslstm_daily_branch_data.add_previous_day_sum_features(df, ["p_aka", "p_bandang"])

    assert "p_aka_prev1d_sum" in enriched.columns
    assert "p_bandang_prev1d_sum" in enriched.columns
    assert enriched.loc["2020-01-01 12:00:00", "p_aka_prev1d_sum"] != enriched.loc[
        "2020-01-01 12:00:00", "p_aka_prev1d_sum"
    ]
    assert enriched.loc["2020-01-02 00:00:00", "p_aka_prev1d_sum"] == 24.0
    assert enriched.loc["2020-01-02 23:00:00", "p_aka_prev1d_sum"] == 24.0
    assert enriched.loc["2020-01-03 05:00:00", "p_aka_prev1d_sum"] == 24.0
    assert enriched.loc["2020-01-02 00:00:00", "p_bandang_prev1d_sum"] == sum(range(24))
    assert enriched.loc["2020-01-02 23:00:00", "p_bandang_prev1d_sum"] == sum(range(24))


def test_build_augmented_dataset_copies_layout_and_adds_prev1d_columns(tmp_path: Path):
    source = tmp_path / "source"
    output = tmp_path / "output"
    (source / "attributes").mkdir(parents=True)
    (source / "time_series").mkdir(parents=True)

    for name in ["basins.txt", "train_basins.txt", "validation_basins.txt", "test_basins.txt"]:
        (source / name).write_text("namou_kuwei\n", encoding="utf-8")
    (source / "attributes" / "attributes.csv").write_text("basin,area\nnamou_kuwei,1.0\n", encoding="utf-8")

    index = pd.date_range("2020-01-01 00:00:00", periods=48, freq="h")
    ds = xr.Dataset(
        {
            "p_aka": ("date", np.ones(len(index), dtype=float)),
            "p_bandang": ("date", np.full(len(index), 2.0, dtype=float)),
            "qobs": ("date", np.arange(len(index), dtype=float)),
        },
        coords={"date": index},
    )
    ds.to_netcdf(source / "time_series" / "namou_kuwei.nc")

    build_mtslstm_daily_branch_data.build_augmented_generic_dataset(
        source_dir=source,
        output_dir=output,
        rainfall_columns=["p_aka", "p_bandang"],
    )

    assert (output / "attributes" / "attributes.csv").exists()
    assert (output / "train_basins.txt").read_text(encoding="utf-8") == "namou_kuwei\n"

    enriched = xr.open_dataset(output / "time_series" / "namou_kuwei.nc")
    assert "p_aka_prev1d_sum" in enriched.data_vars
    assert "p_bandang_prev1d_sum" in enriched.data_vars
    assert "qobs" in enriched.data_vars
    assert float(enriched["p_aka_prev1d_sum"].sel(date="2020-01-02T00:00:00").item()) == 24.0
    assert float(enriched["p_bandang_prev1d_sum"].sel(date="2020-01-02T12:00:00").item()) == 48.0
