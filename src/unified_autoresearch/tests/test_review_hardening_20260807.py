"""Negative cases for gates the 2026-08-07 adversarial review found unguarded.

Every test here was written to fail against the code as it stood at review time. The review's
finding was not that the gates were wrong, but that deleting them left the suite green -- they
were written down rather than enforced. Each test below turns one of them red.
"""

import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from unified_autoresearch.tests.test_scaleup_64_data_base import (
    build_packages,
    build_source,
    frozen_64_basins,
    write_camels_tree,
)


MODULE_ROOT = Path(__file__).resolve().parents[1]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@pytest.fixture(scope="module")
def packages(tmp_path_factory) -> Path:
    root = tmp_path_factory.mktemp("hardening")
    camels_root = write_camels_tree(root / "camels_us", frozen_64_basins())
    build_source(root / "development_source", camels_root)
    build_packages(root / "development_source", root / "packages")
    return root / "packages"


def _copy_with_truth(package_root: Path, destination: Path, protocol: str, frame: pd.DataFrame) -> Path:
    """Copy a package, replace one protocol's truth, and re-seal the manifest over it."""
    shutil.copytree(package_root, destination)
    path = destination / protocol / "score" / "validation_truth.parquet"
    frame.to_parquet(path, index=False)
    manifest_path = destination / "PACKAGE_MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["files"][path.relative_to(destination).as_posix()] = _sha256(path)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return destination


def _predictions_for(truth_path: Path, destination: Path) -> Path:
    frame = pd.read_parquet(truth_path).rename(columns={"qobs": "qsim"})
    frame.to_parquet(destination, index=False)
    return destination


def test_scoring_refuses_truth_that_covers_fewer_basins_than_the_manifest_declares(packages, tmp_path):
    """Dropping unstable basins from truth would lift a headline while still claiming 64 basins."""
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    truth = pd.read_parquet(packages / "forward" / "score" / "validation_truth.parquet")
    truth["basin"] = truth["basin"].astype(str).str.zfill(8)
    kept = set(frozen_64_basins()[:8])
    shrunk = truth.loc[truth["basin"].isin(kept)].reset_index(drop=True)
    tampered = _copy_with_truth(packages, tmp_path / "shrunk", "forward", shrunk)
    predictions = _predictions_for(
        tampered / "forward" / "score" / "validation_truth.parquet", tmp_path / "predictions.parquet"
    )

    with pytest.raises(ValueError, match="development truth must cover every basin the package declares"):
        score_development_predictions(
            package_root=tampered,
            expected_package_manifest_sha256=_sha256(tampered / "PACKAGE_MANIFEST.json"),
            candidate_id="probe-v1",
            category="custom_python",
            registered_run_id="run-0001",
            protocol_name="forward",
            predictions_path=predictions,
            output_path=tmp_path / "score.json",
        )


def _score_report(basins, *, protocol: str, path: Path) -> Path:
    report = {
        "schema_version": "development_score_v1",
        "candidate_id": "probe-v1",
        "category": "custom_python",
        "registered_run_id": f"run-{protocol}-0001",
        "protocol": protocol,
        "row_count": len(basins),
        "basin_metrics": {basin: 0.5 for basin in basins},
        "package_manifest_sha256": "a" * 64,
        "truth_sha256": "b" * 64,
        "predictions_sha256": "c" * 64,
    }
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def test_summarising_refuses_a_basin_set_that_was_never_frozen(tmp_path):
    """This is the gate `_frozen_basin_list` exists for; deleting it must not leave the suite green."""
    from unified_autoresearch.evaluation.scoring import summarize_candidate_development_scores

    unfrozen = frozen_64_basins()[:9]
    paths = {
        protocol: _score_report(unfrozen, protocol=protocol, path=tmp_path / f"{protocol}.json")
        for protocol in ("forward", "reverse")
    }

    with pytest.raises(ValueError, match="development score report identity or source mismatch"):
        summarize_candidate_development_scores(
            candidate_id="probe-v1",
            category="custom_python",
            registered_run_ids={"forward": "run-forward-0001", "reverse": "run-reverse-0001"},
            expected_package_manifest_sha256="a" * 64,
            score_paths=paths,
            output_path=tmp_path / "summary.json",
        )


def _truth_frame(basins, values_for_first, *, days: int) -> pd.DataFrame:
    dates = pd.date_range("2005-10-01", periods=days, freq="D")
    rows = []
    for index, basin in enumerate(basins):
        values = values_for_first(days) if index == 0 else np.linspace(1.0, 5.0, days)
        rows.append(pd.DataFrame({"basin": basin, "date": dates, "qobs": values}))
    return pd.concat(rows, ignore_index=True)


def _single_day_share(values: np.ndarray) -> float:
    squared = (values - values.mean()) ** 2
    return float(squared.max() / squared.sum())


def _two_spike_values(days: int, second_spike: float) -> np.ndarray:
    values = np.ones(days, dtype=float)
    values[0] = 1000.0
    values[1] = second_spike
    return values


@pytest.mark.parametrize("side", ["below", "above"])
def test_the_single_day_variance_threshold_is_pinned_from_both_sides(packages, tmp_path, side):
    """A boundary pair straddling 0.5, so moving the constant either way turns this red."""
    from unified_autoresearch.evaluation.basin_eligibility import classify_development_basins

    days = len(pd.read_parquet(packages / "forward" / "score" / "validation_truth.parquet")) // 64
    low, high = 1.0, 1000.0
    for _ in range(80):
        middle = (low + high) / 2.0
        if _single_day_share(_two_spike_values(days, middle)) < 0.5:
            high = middle
        else:
            low = middle
    # `low` sits just above the threshold and `high` just below it.
    spike = low if side == "above" else high
    values = _two_spike_values(days, spike)
    share = _single_day_share(values)
    assert (share >= 0.5) is (side == "above"), "the boundary search must straddle the threshold"

    basin = frozen_64_basins()[0]
    frame = _truth_frame(frozen_64_basins(), lambda count: values, days=days)
    tampered = _copy_with_truth(packages, tmp_path / f"share_{side}", "forward", frame)

    record = classify_development_basins(
        package_root=tampered,
        expected_package_manifest_sha256=_sha256(tampered / "PACKAGE_MANIFEST.json"),
        output_path=tmp_path / "eligibility.json",
    )

    triggered = "single_day_variance_share" in record["basins"][basin]["reasons"]
    assert triggered is (side == "above")


@pytest.mark.parametrize("side", ["below", "above"])
def test_the_zero_flow_threshold_is_pinned_from_both_sides(packages, tmp_path, side):
    from unified_autoresearch.evaluation.basin_eligibility import classify_development_basins

    days = len(pd.read_parquet(packages / "forward" / "score" / "validation_truth.parquet")) // 64
    zeros = days // 2 if side == "above" else days // 2 - 1

    def values(count: int) -> np.ndarray:
        series = np.linspace(1.0, 5.0, count)
        series[:zeros] = 0.0
        return series

    basin = frozen_64_basins()[0]
    frame = _truth_frame(frozen_64_basins(), values, days=days)
    tampered = _copy_with_truth(packages, tmp_path / f"zero_{side}", "forward", frame)

    record = classify_development_basins(
        package_root=tampered,
        expected_package_manifest_sha256=_sha256(tampered / "PACKAGE_MANIFEST.json"),
        output_path=tmp_path / "eligibility.json",
    )

    triggered = "zero_flow_fraction" in record["basins"][basin]["reasons"]
    assert triggered is (side == "above")


def test_classification_refuses_a_package_whose_basin_set_was_never_frozen(packages, tmp_path):
    from unified_autoresearch.evaluation.basin_eligibility import classify_development_basins

    tampered = tmp_path / "unfrozen"
    shutil.copytree(packages, tampered)
    manifest_path = tampered / "PACKAGE_MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["basins"] = manifest["basins"][:5]
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    with pytest.raises(ValueError, match="basin set is not one of the frozen development selections"):
        classify_development_basins(
            package_root=tampered,
            expected_package_manifest_sha256=_sha256(manifest_path),
            output_path=tmp_path / "eligibility.json",
        )


def _eligibility(standard, unstable) -> dict:
    from unified_autoresearch.evaluation.basin_eligibility import SCHEMA_VERSION

    return {
        "schema_version": SCHEMA_VERSION,
        "standard_basins": list(standard),
        "unstable_basins": list(unstable),
        "thresholds": {"zero_flow_fraction_at_or_above": 0.5, "single_day_variance_share_at_or_above": 0.5},
    }


def test_partitioning_refuses_a_basin_listed_twice_in_one_group():
    """Guarding only against a missing basin lets a duplicate inflate the headline group."""
    from unified_autoresearch.evaluation.basin_eligibility import partition_summary_cells

    basins = frozen_64_basins()[:4]
    eligibility = _eligibility([basins[0], basins[0], basins[1]], [basins[2]])
    cells = [{"basin": basin, "mean_nse": 0.5} for basin in basins[:3]]

    with pytest.raises(ValueError, match="classified basins must be unique and must not overlap"):
        partition_summary_cells(cells=cells, eligibility=eligibility)


def test_partitioning_refuses_a_basin_in_both_groups():
    from unified_autoresearch.evaluation.basin_eligibility import partition_summary_cells

    basins = frozen_64_basins()[:3]
    eligibility = _eligibility([basins[0], basins[1]], [basins[1], basins[2]])
    cells = [{"basin": basin, "mean_nse": 0.5} for basin in basins]

    with pytest.raises(ValueError, match="classified basins must be unique and must not overlap"):
        partition_summary_cells(cells=cells, eligibility=eligibility)


def test_calibration_actually_searches_rather_than_returning_the_starting_point():
    """The previous assertion was satisfied by a search that never ran; this one is not."""
    from unified_autoresearch.candidates.implementations import hbv_lite

    days = 240
    rows = [
        {
            "basin": "01000001",
            "date": f"day-{index:05d}",
            "date_key": f"day-{index:05d}",
            "prcp": 12.0 if index % 9 == 0 else 0.2,
            "tmin": 4.0,
            "tmax": 16.0,
            "srad": 150.0,
            "vp": 1000.0,
        }
        for index in range(days)
    ]
    observed = [3.5 if index % 9 in (1, 2) else 0.2 for index in range(days)]
    targets = {(row["basin"], row["date_key"]): observed[index] for index, row in enumerate(rows)}
    statics = {
        "schema_version": "development_static_attributes_v1",
        "basins": {"01000001": {"pet_mean": 2.0}},
    }

    payload = hbv_lite.train_model(rows, targets, statics, seed=17)
    entry = payload["basins"]["01000001"]

    # Beating the untuned starting point is satisfied by random draws alone, so the binding
    # assertion is that evolution beats the best member the initial population already contained.
    assert entry["training_objective"] > entry["initial_population_objective"] + 1e-6
    assert entry["training_objective"] > entry["initial_objective"] + 1e-6
    assert entry["parameters"] != dict(hbv_lite.INITIAL_PARAMETERS)
