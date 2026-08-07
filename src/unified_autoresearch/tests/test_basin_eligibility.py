"""Basins where Nash--Sutcliffe efficiency is meaningless must be declared before any search.

The classification reads validation truth only. It never sees a candidate prediction, so it
cannot be tuned after the fact to favour a result.
"""

import json
from pathlib import Path

import pandas as pd
import pytest

from unified_autoresearch.tests.test_scaleup_64_data_base import (
    build_packages,
    build_source,
    frozen_64_basins,
    write_camels_tree,
)


def _sha256(path: Path) -> str:
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


@pytest.fixture(scope="module")
def packages(tmp_path_factory) -> Path:
    root = tmp_path_factory.mktemp("eligibility")
    camels_root = write_camels_tree(root / "camels_us", frozen_64_basins())
    source_root = root / "development_source"
    package_root = root / "packages"
    build_source(source_root, camels_root)
    build_packages(source_root, package_root)
    return package_root


def _classify(package_root: Path, output_path: Path) -> dict:
    from unified_autoresearch.evaluation.basin_eligibility import classify_development_basins

    return classify_development_basins(
        package_root=package_root,
        expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
        output_path=output_path,
    )


def _retruth(package_root: Path, destination: Path, protocol: str, basin: str, values) -> Path:
    """Copy the packages and overwrite one basin's validation truth, refreshing the manifest."""
    import shutil

    shutil.copytree(package_root, destination)
    path = destination / protocol / "score" / "validation_truth.parquet"
    frame = pd.read_parquet(path)
    mask = frame["basin"].astype(str).str.zfill(8) == basin
    frame.loc[mask, "qobs"] = values(int(mask.sum()))
    frame.to_parquet(path, index=False)
    manifest_path = destination / "PACKAGE_MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["files"][path.relative_to(destination).as_posix()] = _sha256(path)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return destination


def test_classification_declares_thresholds_and_covers_every_basin(packages, tmp_path):
    from unified_autoresearch.evaluation.basin_eligibility import (
        SINGLE_DAY_VARIANCE_SHARE_LIMIT,
        ZERO_FLOW_FRACTION_LIMIT,
    )

    record = _classify(packages, tmp_path / "eligibility.json")

    assert record["schema_version"] == "basin_eligibility_v1"
    assert record["decided_from"] == "validation truth only; no candidate prediction is read"
    assert record["thresholds"] == {
        "zero_flow_fraction_at_or_above": ZERO_FLOW_FRACTION_LIMIT,
        "single_day_variance_share_at_or_above": SINGLE_DAY_VARIANCE_SHARE_LIMIT,
    }
    assert set(record["basins"]) == set(frozen_64_basins())
    assert sorted(record["standard_basins"] + record["unstable_basins"]) == sorted(frozen_64_basins())
    assert set(record["standard_basins"]) & set(record["unstable_basins"]) == set()


def test_classification_reports_both_protocols_for_every_basin(packages, tmp_path):
    record = _classify(packages, tmp_path / "eligibility.json")

    for entry in record["basins"].values():
        assert set(entry["protocols"]) == {"forward", "reverse"}
        for statistics in entry["protocols"].values():
            assert statistics["days"] > 0
            assert 0.0 <= statistics["zero_flow_fraction"] <= 1.0
            assert 0.0 <= statistics["single_day_variance_share"] <= 1.0


def test_classification_is_written_once_and_refuses_to_overwrite(packages, tmp_path):
    output = tmp_path / "eligibility.json"
    record = _classify(packages, output)

    assert json.loads(output.read_text(encoding="utf-8")) == record
    with pytest.raises(FileExistsError):
        _classify(packages, output)


def test_classification_is_deterministic_byte_for_byte(packages, tmp_path):
    first = tmp_path / "first.json"
    second = tmp_path / "second.json"

    _classify(packages, first)
    _classify(packages, second)

    assert first.read_bytes() == second.read_bytes()


def test_a_basin_that_is_dry_most_of_the_validation_window_is_unstable(packages, tmp_path):
    import numpy as np

    basin = frozen_64_basins()[0]

    def mostly_zero(count: int) -> np.ndarray:
        values = np.zeros(count, dtype=float)
        values[: max(1, count // 4)] = np.linspace(1.0, 5.0, max(1, count // 4))
        return values

    tampered = _retruth(packages, tmp_path / "dry", "forward", basin, mostly_zero)
    record = _classify(tampered, tmp_path / "eligibility.json")

    entry = record["basins"][basin]
    assert entry["status"] == "unstable"
    assert "zero_flow_fraction" in entry["reasons"]
    assert entry["protocols"]["forward"]["zero_flow_fraction"] >= 0.5
    assert basin in record["unstable_basins"]


def test_a_basin_whose_score_hangs_on_one_day_is_unstable(packages, tmp_path):
    import numpy as np

    basin = frozen_64_basins()[1]

    def one_spike(count: int) -> np.ndarray:
        values = np.full(count, 1.0, dtype=float)
        values[0] = 1.0e6
        return values

    tampered = _retruth(packages, tmp_path / "spike", "reverse", basin, one_spike)
    record = _classify(tampered, tmp_path / "eligibility.json")

    entry = record["basins"][basin]
    assert entry["status"] == "unstable"
    assert "single_day_variance_share" in entry["reasons"]
    assert entry["protocols"]["reverse"]["single_day_variance_share"] >= 0.5


def test_a_basin_with_no_variance_is_unstable_rather_than_an_exception(packages, tmp_path):
    import numpy as np

    basin = frozen_64_basins()[2]
    tampered = _retruth(packages, tmp_path / "flat", "forward", basin, lambda count: np.full(count, 3.0))

    record = _classify(tampered, tmp_path / "eligibility.json")

    entry = record["basins"][basin]
    assert entry["status"] == "unstable"
    assert "zero_variance" in entry["reasons"]
    assert entry["protocols"]["forward"]["single_day_variance_share"] == 1.0


def test_classification_rejects_a_package_whose_manifest_digest_does_not_match(packages, tmp_path):
    from unified_autoresearch.evaluation.basin_eligibility import classify_development_basins

    with pytest.raises(ValueError, match="development package manifest differs from the frozen digest"):
        classify_development_basins(
            package_root=packages,
            expected_package_manifest_sha256="0" * 64,
            output_path=tmp_path / "eligibility.json",
        )
    assert not (tmp_path / "eligibility.json").exists()


def test_partitioning_a_candidate_summary_never_silently_drops_a_basin(packages, tmp_path):
    from unified_autoresearch.evaluation.basin_eligibility import partition_summary_cells

    record = _classify(packages, tmp_path / "eligibility.json")
    cells = [{"basin": basin, "mean_nse": 0.5} for basin in frozen_64_basins()]

    partition = partition_summary_cells(cells=cells, eligibility=record)

    assert len(partition["standard"]) + len(partition["unstable"]) == len(cells)
    assert [cell["basin"] for cell in partition["standard"]] == record["standard_basins"]
    assert [cell["basin"] for cell in partition["unstable"]] == record["unstable_basins"]
    assert partition["headline_basin_count"] == len(record["standard_basins"])


def test_partitioning_refuses_a_summary_that_does_not_cover_the_classified_basins(packages, tmp_path):
    from unified_autoresearch.evaluation.basin_eligibility import partition_summary_cells

    record = _classify(packages, tmp_path / "eligibility.json")
    cells = [{"basin": basin, "mean_nse": 0.5} for basin in frozen_64_basins()[:-1]]

    with pytest.raises(ValueError, match="summary cells must cover exactly the classified basins"):
        partition_summary_cells(cells=cells, eligibility=record)
