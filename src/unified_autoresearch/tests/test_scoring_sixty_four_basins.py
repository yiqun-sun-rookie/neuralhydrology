"""Scoring must accept the frozen sixty-four-basin packages, and only frozen basin sets."""

import hashlib
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


PACKAGE_SHA_FIELD = "package_manifest_sha256"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@pytest.fixture(scope="module")
def packages(tmp_path_factory) -> Path:
    root = tmp_path_factory.mktemp("scoring64")
    camels_root = write_camels_tree(root / "camels_us", frozen_64_basins())
    build_source(root / "development_source", camels_root)
    build_packages(root / "development_source", root / "packages")
    return root / "packages"


def _predictions(package_root: Path, protocol_name: str, destination: Path, *, offset: float = 0.0) -> Path:
    truth = pd.read_parquet(package_root / protocol_name / "score" / "validation_truth.parquet")
    frame = truth.rename(columns={"qobs": "qsim"})
    frame["qsim"] = frame["qsim"].astype(float) + offset
    frame.to_parquet(destination, index=False)
    return destination


def _score(package_root: Path, protocol_name: str, tmp_path: Path, *, offset: float = 0.0) -> dict:
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    predictions = _predictions(package_root, protocol_name, tmp_path / f"{protocol_name}_predictions.parquet", offset=offset)
    return score_development_predictions(
        package_root=package_root,
        expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
        candidate_id="reference_zero_v1",
        category="custom_python",
        registered_run_id=f"run_{protocol_name}_0001",
        protocol_name=protocol_name,
        predictions_path=predictions,
        output_path=tmp_path / f"{protocol_name}_score.json",
    )


def test_scoring_accepts_a_sixty_four_basin_package_and_reports_every_basin(packages, tmp_path):
    report = _score(packages, "forward", tmp_path)

    assert set(report["basin_metrics"]) == set(frozen_64_basins())
    assert len(report["basin_metrics"]) == 64
    assert all(abs(value - 1.0) < 1e-12 for value in report["basin_metrics"].values())


def test_summarising_two_protocols_produces_one_cell_per_frozen_basin(packages, tmp_path):
    from unified_autoresearch.evaluation.scoring import summarize_candidate_development_scores

    _score(packages, "forward", tmp_path)
    _score(packages, "reverse", tmp_path)

    summary = summarize_candidate_development_scores(
        candidate_id="reference_zero_v1",
        category="custom_python",
        registered_run_ids={"forward": "run_forward_0001", "reverse": "run_reverse_0001"},
        expected_package_manifest_sha256=_sha256(packages / "PACKAGE_MANIFEST.json"),
        score_paths={"forward": tmp_path / "forward_score.json", "reverse": tmp_path / "reverse_score.json"},
        output_path=tmp_path / "summary.json",
    )

    assert summary["cell_count"] == 64
    assert [cell["basin"] for cell in summary["cells"]] == frozen_64_basins()


def test_scoring_refuses_a_package_whose_basin_list_is_not_a_frozen_set(packages, tmp_path):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    tampered = tmp_path / "tampered_packages"
    import shutil

    shutil.copytree(packages, tampered)
    manifest_path = tampered / "PACKAGE_MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["basins"] = manifest["basins"][:-1]
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    predictions = _predictions(tampered, "forward", tmp_path / "predictions.parquet")

    with pytest.raises(ValueError, match="development package manifest mismatch"):
        score_development_predictions(
            package_root=tampered,
            expected_package_manifest_sha256=_sha256(manifest_path),
            candidate_id="reference_zero_v1",
            category="custom_python",
            registered_run_id="run_forward_0001",
            protocol_name="forward",
            predictions_path=predictions,
            output_path=tmp_path / "score.json",
        )


def test_summary_partitions_cleanly_against_the_basin_eligibility_record(packages, tmp_path):
    from unified_autoresearch.evaluation.basin_eligibility import (
        classify_development_basins,
        partition_summary_cells,
    )
    from unified_autoresearch.evaluation.scoring import summarize_candidate_development_scores

    digest = _sha256(packages / "PACKAGE_MANIFEST.json")
    _score(packages, "forward", tmp_path)
    _score(packages, "reverse", tmp_path)
    summary = summarize_candidate_development_scores(
        candidate_id="reference_zero_v1",
        category="custom_python",
        registered_run_ids={"forward": "run_forward_0001", "reverse": "run_reverse_0001"},
        expected_package_manifest_sha256=digest,
        score_paths={"forward": tmp_path / "forward_score.json", "reverse": tmp_path / "reverse_score.json"},
        output_path=tmp_path / "summary.json",
    )
    eligibility = classify_development_basins(
        package_root=packages,
        expected_package_manifest_sha256=digest,
        output_path=tmp_path / "eligibility.json",
    )

    partition = partition_summary_cells(cells=summary["cells"], eligibility=eligibility)

    assert partition["headline_basin_count"] + partition["unstable_basin_count"] == 64
