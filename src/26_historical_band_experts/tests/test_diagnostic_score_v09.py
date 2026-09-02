"""Diagnostic scoring tests.

The point of these is that a diagnostic run can never masquerade as the pre-registered
clean-pair verdict, and that the gate arithmetic matches the contract's primary gate.
"""
from pathlib import Path
import json
import sys

import numpy as np
import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))
sys.path.insert(0, str(IDEA_ROOT.parent))

_FAMILIES = ("B09-CLASSIC", "B09-CAPACITY", "E09-CONTINUOUS")
_DAYS = 40


def _write_long(path: Path, basins, dates, values_by_basin, column):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"basin,date,{column}"]
    for basin in basins:
        series = values_by_basin[basin]
        for index, date in enumerate(dates):
            lines.append(f"{basin},{date},{series[index]!r}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _build_case(tmp_path: Path, challenger_gain: float, basin_count: int = 12) -> tuple[Path, Path]:
    rng = np.random.default_rng(0)
    basins = [f"{index:08d}" for index in range(1, basin_count + 1)]
    dates = [str(date.date()) for date in
             __import__("pandas").date_range("1989-10-01", periods=_DAYS, freq="D")]

    observations = {basin: rng.gamma(2.0, 1.5, size=_DAYS) for basin in basins}
    _write_long(tmp_path / "obs.csv", basins, dates, observations, "qobs")

    predictions_root = tmp_path / "predictions"
    # A larger error multiplier means a worse model; the challenger's is smaller by `gain`.
    error_scale = {"B09-CLASSIC": 0.60, "B09-CAPACITY": 0.50, "E09-CONTINUOUS": 0.50 - challenger_gain}
    for family in _FAMILIES:
        noise = rng.normal(0.0, 1.0, size=(basin_count, _DAYS))
        values = {
            basin: observations[basin] + error_scale[family] * noise[index]
            for index, basin in enumerate(basins)
        }
        _write_long(predictions_root / "ensembles" / f"{family}_ensemble.csv", basins, dates, values, "qsim")

    manifest = {
        "schema": "historical_multiscale_formal_v09_predictions_root_v1",
        "status": "formal_predictions_complete",
        "run_order_canonical_sha256": "a" * 64,
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "official_score_called": False,
    }
    (predictions_root / "manifest.json").write_text(json.dumps(manifest, sort_keys=True), encoding="utf-8")
    return predictions_root, tmp_path / "obs.csv"


def test_report_is_marked_diagnostic_and_nonqualifying(tmp_path):
    from diagnostic_score_v09 import diagnostic_compare_v09

    predictions_root, answer_key = _build_case(tmp_path, challenger_gain=0.25)
    report = diagnostic_compare_v09(
        predictions_root, answer_key, require_answer_key_hash=False, require_formal_geometry=False)

    assert report["diagnostic_only"] is True
    assert report["qualifying"] is False
    assert report["official_score_called"] is False
    assert report["postseal_holdout_drawn"] is False
    assert report["score_ledger_appended"] is False
    assert report["one_call_authorization_consumed"] is False
    assert "clean_pair" not in report["verdict_authority"].replace("clean_pair_route", "")


def test_a_real_gain_passes_every_primary_gate_check(tmp_path):
    from diagnostic_score_v09 import diagnostic_compare_v09

    predictions_root, answer_key = _build_case(tmp_path, challenger_gain=0.25)
    report = diagnostic_compare_v09(
        predictions_root, answer_key, require_answer_key_hash=False, require_formal_geometry=False)

    assert report["primary_comparison_challenger_vs_capacity"]["median_paired_delta"] > 0.01
    assert report["all_primary_gate_checks_pass"] is True


def test_no_gain_fails_the_effect_size_check(tmp_path):
    from diagnostic_score_v09 import diagnostic_compare_v09

    predictions_root, answer_key = _build_case(tmp_path, challenger_gain=0.0)
    report = diagnostic_compare_v09(
        predictions_root, answer_key, require_answer_key_hash=False, require_formal_geometry=False)

    assert report["primary_comparison_challenger_vs_capacity"]["median_paired_delta"] < 0.01
    assert report["primary_gate_checks"]["effect_at_least_min"] is False
    assert report["all_primary_gate_checks_pass"] is False


def test_primary_gate_reference_matches_the_scoring_contract(tmp_path):
    from diagnostic_score_v09 import _PRIMARY_GATE

    contract = json.loads(
        (IDEA_ROOT / "configs/formal_v09_clean_pair_scoring_contract.json").read_text(encoding="utf-8"))
    gate = contract["primary_gate"]
    for key, value in _PRIMARY_GATE.items():
        assert gate[key] == value, key


def test_answer_key_hash_drift_is_refused(tmp_path):
    from diagnostic_score_v09 import DiagnosticScoreError, diagnostic_compare_v09

    predictions_root, answer_key = _build_case(tmp_path, challenger_gain=0.1)
    with pytest.raises(DiagnosticScoreError, match="answer key hash drift"):
        diagnostic_compare_v09(
            predictions_root, answer_key, require_answer_key_hash=True, require_formal_geometry=False)


def test_prediction_manifest_claiming_a_prior_score_is_refused(tmp_path):
    from diagnostic_score_v09 import DiagnosticScoreError, diagnostic_compare_v09

    predictions_root, answer_key = _build_case(tmp_path, challenger_gain=0.1)
    manifest = json.loads((predictions_root / "manifest.json").read_text(encoding="utf-8"))
    manifest["official_score_called"] = True
    (predictions_root / "manifest.json").write_text(json.dumps(manifest, sort_keys=True), encoding="utf-8")
    with pytest.raises(DiagnosticScoreError):
        diagnostic_compare_v09(
            predictions_root, answer_key, require_answer_key_hash=False, require_formal_geometry=False)


def test_missing_ensemble_is_refused(tmp_path):
    from diagnostic_score_v09 import DiagnosticScoreError, diagnostic_compare_v09

    predictions_root, answer_key = _build_case(tmp_path, challenger_gain=0.1)
    (predictions_root / "ensembles" / "E09-CONTINUOUS_ensemble.csv").unlink()
    with pytest.raises(DiagnosticScoreError, match="missing ensemble prediction"):
        diagnostic_compare_v09(
            predictions_root, answer_key, require_answer_key_hash=False, require_formal_geometry=False)


def test_answer_key_hash_constant_matches_the_frozen_manifest():
    from diagnostic_score_v09 import _ANSWER_KEY_SHA256

    manifest = (IDEA_ROOT.parent / "fair_benchmark/frozen/MANIFEST.sha256").read_text(encoding="utf-8")
    entry = [line for line in manifest.splitlines() if line.endswith("track0_forcing_only_obs_eval.parquet")]
    assert len(entry) == 1
    assert entry[0].split()[0] == _ANSWER_KEY_SHA256
