"""load_track consumes the spec.yaml contract.

The spec is the single source of truth for a track: load_track must (a) enforce
the human-confirmed gate (refuse to build a Track from an unconfirmed spec) and
(b) derive the gate thresholds + frozen-file locations from the spec, so the
spec is consumed rather than being inert documentation alongside the files.
"""
import pandas as pd
import pytest

from fair_benchmark.gate import GateConfig
from fair_benchmark.tracks import TrackNotConfirmedError, load_track

NAME = "track0_forcing_only"


def _write_frozen(tmp_path, *, confirmed, min_effect=0.01, gate_lines=None):
    """Write a minimal frozen set: spec.yaml + the three files it references."""
    (tmp_path / f"{NAME}_baseline_per_basin_nse.csv").write_text(
        "basin,NSE\n00000001,0.60\n00000002,0.70\n00000003,0.50\n", encoding="utf-8")
    (tmp_path / f"{NAME}_secret_holdout_basins.txt").write_text("00000003\n", encoding="utf-8")
    pd.DataFrame({"basin": ["00000001", "00000001"],
                  "date": ["1990-01-01", "1990-01-02"],
                  "qobs": [1.0, 2.0]}).to_csv(tmp_path / f"{NAME}_obs_eval.csv", index=False)

    lines = [
        f"track: {NAME}",
        f"confirmed: {str(confirmed).lower()}",
        "metric:",
        "  name: NSE",
        f"  min_meaningful_effect: {min_effect}",
        f"secret_holdout_file: {NAME}_secret_holdout_basins.txt",
        f"baseline_nse_vector: {NAME}_baseline_per_basin_nse.csv",
        f"answer_key_held: {NAME}_obs_eval.csv",
    ]
    if gate_lines:
        lines += gate_lines
    (tmp_path / f"{NAME}.spec.yaml").write_text("\n".join(lines) + "\n", encoding="utf-8")


def test_unconfirmed_spec_refuses_to_load(tmp_path):
    _write_frozen(tmp_path, confirmed=False)
    with pytest.raises(TrackNotConfirmedError):
        load_track(NAME, tmp_path)


def test_unconfirmed_loads_only_when_explicitly_allowed(tmp_path):
    _write_frozen(tmp_path, confirmed=False)
    track = load_track(NAME, tmp_path, require_confirmed=False)
    assert track.baseline_nse["00000002"] == 0.70


def test_confirmed_spec_loads_and_derives_gate_threshold(tmp_path):
    _write_frozen(tmp_path, confirmed=True, min_effect=0.025)
    track = load_track(NAME, tmp_path)
    # min_effect comes from the spec, not the GateConfig default (0.01)
    assert track.gate_cfg.min_effect == 0.025
    assert track.gate_cfg != GateConfig()
    assert track.secret_holdout == {"00000003"}
    assert set(track.baseline_nse) == {"00000001", "00000002", "00000003"}
    assert track.obs["00000001"].iloc[1] == 2.0
    assert track.spec["track"] == NAME


def test_explicit_gate_block_overrides_defaults(tmp_path):
    _write_frozen(tmp_path, confirmed=True,
                  gate_lines=["gate:", "  holdout_retention: 0.7", "  max_wilcoxon_p: 0.01"])
    track = load_track(NAME, tmp_path)
    assert track.gate_cfg.holdout_retention == 0.7
    assert track.gate_cfg.max_wilcoxon_p == 0.01


def test_missing_spec_falls_back_to_naming_convention(tmp_path):
    # No spec.yaml -> load by the historical naming convention, default gate cfg.
    _write_frozen(tmp_path, confirmed=True)
    (tmp_path / f"{NAME}.spec.yaml").unlink()
    track = load_track(NAME, tmp_path)
    assert set(track.baseline_nse) == {"00000001", "00000002", "00000003"}
    assert track.gate_cfg == GateConfig()
    assert track.spec is None
