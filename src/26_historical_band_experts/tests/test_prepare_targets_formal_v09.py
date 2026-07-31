import inspect
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG = IDEA_ROOT / "configs/formal_v09_protocol.json"
sys.path.insert(0, str(IDEA_ROOT))


def _series(offset: float = 0.0) -> pd.Series:
    dates = pd.date_range("1989-10-01", "2008-09-30", freq="D")
    return pd.Series(np.arange(len(dates), dtype=np.float64) + offset, index=dates)


def test_synthetic_streaming_writer_emits_only_training_validation_window(tmp_path):
    from prepare_targets_formal_v09 import write_synthetic_target_bundle_v09

    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("00000001\n00000002\n", encoding="utf-8")
    output = tmp_path / "synthetic_targets.csv"
    loaded = []
    checkpoints = []

    manifest = write_synthetic_target_bundle_v09(
        basins=("1", "2"),
        basin_file=basin_file,
        output_path=output,
        load_one=lambda basin: loaded.append(basin) or _series(float(basin)),
        checkpoint=lambda: checkpoints.append(True),
    )

    frame = pd.read_csv(output, dtype={"basin": str})
    manifest_on_disk = json.loads(output.with_suffix(".manifest.json").read_text("utf-8"))
    assert loaded == ["00000001", "00000002"]
    assert len(checkpoints) == 3
    assert list(frame.columns) == ["basin", "date", "qobs"]
    assert frame["basin"].str.zfill(8).tolist()[:2] == ["00000001", "00000001"]
    assert len(frame) == 2 * 3_288
    assert frame["date"].min() == "1999-10-01"
    assert frame["date"].max() == "2008-09-30"
    assert manifest["formal_evaluation_rows_emitted"] == 0
    assert manifest["writer"] == "stream_one_basin_v1"
    assert manifest_on_disk == manifest
    assert "qobs" not in manifest
    assert "values" not in manifest


def test_streaming_writer_rejects_basin_order_drift_before_reading_targets(tmp_path):
    from prepare_targets_formal_v09 import write_synthetic_target_bundle_v09

    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("00000001\n00000002\n", encoding="utf-8")
    called = []

    with pytest.raises(ValueError, match="basin sequence"):
        write_synthetic_target_bundle_v09(
            basins=("2", "1"),
            basin_file=basin_file,
            output_path=tmp_path / "synthetic_targets.csv",
            load_one=lambda basin: called.append(basin) or _series(),
        )

    assert called == []


def test_formal_basin_file_requires_frozen_count_and_hash():
    from prepare_targets_formal_v09 import _validate_formal_basin_file_v09

    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    frozen_basin_file = IDEA_ROOT.parents[1] / config["basin_file"]

    basin_ids = _validate_formal_basin_file_v09(config, frozen_basin_file)

    assert len(basin_ids) == 531
    assert basin_ids[0].isdigit()


def test_synthetic_writer_rejects_every_path_inside_formal_result_root(
    tmp_path,
    monkeypatch,
):
    import prepare_targets_formal_v09 as target_module

    monkeypatch.setattr(target_module, "WORKTREE_ROOT", tmp_path)
    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("00000001\n", encoding="utf-8")
    formal_output = (
        tmp_path
        / "results/26_historical_band_experts/formal_v09/not_the_registered_name.csv"
    )

    with pytest.raises(ValueError, match="formal result tree"):
        target_module.write_synthetic_target_bundle_v09(
            basins=("1",),
            basin_file=basin_file,
            output_path=formal_output,
            load_one=lambda basin: _series(),
        )

    assert not formal_output.parent.exists()


def test_private_writer_also_rejects_formal_tree_without_runtime_capability(
    tmp_path,
    monkeypatch,
):
    import prepare_targets_formal_v09 as target_module

    monkeypatch.setattr(target_module, "WORKTREE_ROOT", tmp_path)
    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("00000001\n", encoding="utf-8")
    formal_output = tmp_path / target_module.FORMAL_RELATIVE_OUTPUT

    with pytest.raises(ValueError, match="authorized runtime capability"):
        target_module._write_streaming_target_bundle_v09(
            basins=("1",),
            basin_file=basin_file,
            output_path=formal_output,
            load_one=lambda basin: _series(),
        )

    assert not formal_output.parent.exists()


def test_training_window_reader_never_parses_evaluation_qobs(tmp_path):
    from prepare_targets_formal_v09 import (
        _load_training_discharge_window_v09,
        _scan_date_prefix_v09,
    )

    source = tmp_path / "00000001_streamflow_qc.txt"
    source.write_text(
        "00000001 1999 9 30 SEALED_EVALUATION_VALUE A\n"
        "00000001 1999 10 1 10.0 A\n"
        "00000001 2008 9 30 20.0 A\n"
        "00000001 2008 10 1 SEALED_POST_WINDOW_VALUE A\n",
        encoding="utf-8",
    )

    series = _load_training_discharge_window_v09(source, area=100)

    assert series.index.tolist() == [pd.Timestamp("1999-10-01"), pd.Timestamp("2008-09-30")]
    assert np.isfinite(series.to_numpy()).all()
    prefix, remainder_offset = _scan_date_prefix_v09(
        "00000001 1999 9 30 SEALED_EVALUATION_VALUE A\n",
        line_number=1,
    )
    assert prefix == ("00000001", "1999", "9", "30")
    assert "SEALED_EVALUATION_VALUE" not in prefix
    assert remainder_offset < len("00000001 1999 9 30 SEALED_EVALUATION_VALUE A\n")


def test_reparse_point_in_formal_parent_is_rejected(tmp_path, monkeypatch):
    import prepare_targets_formal_v09 as target_module

    parent = tmp_path / "results"
    parent.mkdir()
    monkeypatch.setattr(
        target_module,
        "_is_reparse_point_v09",
        lambda path: Path(path) == parent,
    )

    with pytest.raises(ValueError, match="reparse point"):
        target_module._assert_no_reparse_components_v09(tmp_path, parent / "formal_v09")


def test_streaming_writer_removes_partial_artifacts_on_failure(tmp_path):
    from prepare_targets_formal_v09 import write_synthetic_target_bundle_v09

    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("00000001\n00000002\n", encoding="utf-8")
    output = tmp_path / "synthetic_targets.csv"

    def load_one(basin):
        if basin == "00000002":
            raise RuntimeError("synthetic read failure")
        return _series()

    with pytest.raises(RuntimeError, match="synthetic read failure"):
        write_synthetic_target_bundle_v09(
            basins=("1", "2"),
            basin_file=basin_file,
            output_path=output,
            load_one=load_one,
        )

    assert not output.exists()
    assert not output.with_suffix(".csv.tmp").exists()
    assert not output.with_suffix(".manifest.json").exists()
    assert not output.with_suffix(".manifest.json.tmp").exists()


def test_streaming_writer_removes_completed_csv_if_manifest_publish_fails(
    tmp_path,
    monkeypatch,
):
    import prepare_targets_formal_v09 as target_module

    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("00000001\n", encoding="utf-8")
    output = tmp_path / "synthetic_targets.csv"
    real_replace = target_module.os.replace
    calls = []

    def fail_second_replace(source, destination):
        calls.append((source, destination))
        if len(calls) == 2:
            raise OSError("synthetic manifest publish failure")
        return real_replace(source, destination)

    monkeypatch.setattr(target_module.os, "replace", fail_second_replace)
    with pytest.raises(OSError, match="manifest publish failure"):
        target_module.write_synthetic_target_bundle_v09(
            basins=("1",),
            basin_file=basin_file,
            output_path=output,
            load_one=lambda basin: _series(),
        )

    assert not output.exists()
    assert not output.with_suffix(".csv.tmp").exists()
    assert not output.with_suffix(".manifest.json").exists()
    assert not output.with_suffix(".manifest.json.tmp").exists()


def test_formal_entry_is_fixed_path_and_reads_nothing_while_authorization_closed(
    tmp_path,
    monkeypatch,
):
    import prepare_targets_formal_v09 as target_module
    from launch_gate_v09 import LaunchAuthorizationError

    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    monkeypatch.setattr(target_module, "WORKTREE_ROOT", tmp_path)

    with pytest.raises(LaunchAuthorizationError, match="not authorized"):
        target_module.prepare_formal_target_bundle_v09(config)

    formal_output = tmp_path / config["formal_action_resources"]["target_bundle"]["output_path"]
    assert not formal_output.exists()
    assert not formal_output.parent.exists()


def test_formal_target_entry_cli_has_no_output_override():
    from prepare_targets_formal_v09 import prepare_formal_target_bundle_v09

    completed = subprocess.run(
        [sys.executable, str(IDEA_ROOT / "prepare_targets_formal_v09.py"), "--help"],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )

    assert completed.returncode == 0
    assert "--data-dir" not in completed.stdout
    assert "--basin-file" not in completed.stdout
    assert "--out" not in completed.stdout
    assert set(inspect.signature(prepare_formal_target_bundle_v09).parameters) == {"config"}
