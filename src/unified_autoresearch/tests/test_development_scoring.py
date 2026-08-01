import hashlib
import json
import os
from pathlib import Path

import pandas as pd
import pytest

from unified_autoresearch.selection.basins import APPROVED_STATIC_ATTRIBUTES


MODULE_ROOT = Path(__file__).resolve().parents[1]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _build_packages(tmp_path: Path) -> Path:
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_root.mkdir()
    basins = json.loads((MODULE_ROOT / "selection" / "development_basins_v1.json").read_text(encoding="utf-8"))[
        "basins"
    ]
    dates = pd.to_datetime(
        ["1999-10-01", "2002-09-30", "2002-10-01", "2005-09-30", "2005-10-01", "2008-09-30"]
    )
    features = []
    targets = []
    for basin_index, basin in enumerate(basins):
        for date_index, date in enumerate(dates):
            features.append(
                {
                    "basin": basin,
                    "date": date,
                    "prcp": float(date_index + 1),
                    "tmin": float(basin_index),
                    "tmax": float(basin_index + 10),
                    "srad": float(date_index + 100),
                    "vp": float(date_index + 1000),
                }
            )
            targets.append({"basin": basin, "date": date, "qobs": float(basin_index * 10 + date_index + 1)})
    pd.DataFrame(features).to_parquet(source_root / "features.parquet", index=False)
    pd.DataFrame(targets).to_parquet(source_root / "targets.parquet", index=False)
    (source_root / "static_attributes.json").write_text(
        json.dumps(
            {
                "schema_version": "development_static_attributes_v1",
                "basins": {
                    basin: {
                        name: float(basin_index + attribute_index + 1)
                        for attribute_index, name in enumerate(APPROVED_STATIC_ATTRIBUTES)
                    }
                    for basin_index, basin in enumerate(basins)
                },
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    manifest_path = source_root / "SOURCE_MANIFEST.json"
    manifest_path.write_text(
        json.dumps(
            {
                "schema_version": "development_source_v1",
                "source_kind": "explicitly_pre_sliced_development_only",
                "forcing_product": "maurer",
                "date_bounds": ["1999-10-01", "2008-09-30"],
                "sealed_final_evaluation_present": False,
                "files": {
                    name: _sha256(source_root / name)
                    for name in ("features.parquet", "targets.parquet", "static_attributes.json")
                },
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    package_root = tmp_path / "packages"
    build_development_packages(
        source_root=source_root,
        source_manifest_path=manifest_path,
        protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
        selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
        output_root=package_root,
    )
    return package_root


def _score(package_root: Path, protocol_name: str, predictions_path: Path, output_path: Path) -> dict:
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    return score_development_predictions(
        package_root=package_root,
        expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
        candidate_id="reference-custom-python-v1",
        category="custom_python",
        registered_run_id=f"reference-custom-python-v1-{protocol_name}-run",
        protocol_name=protocol_name,
        predictions_path=predictions_path,
        output_path=output_path,
    )


def test_external_development_scorer_writes_perfect_basin_metrics(tmp_path):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    package_root = _build_packages(tmp_path)
    truth = pd.read_parquet(package_root / "forward" / "score" / "validation_truth.parquet")
    predictions_path = tmp_path / "predictions.parquet"
    truth.rename(columns={"qobs": "qsim"}).to_parquet(predictions_path, index=False)
    output_path = tmp_path / "development-score.json"

    report = _score(
        package_root=package_root,
        protocol_name="forward",
        predictions_path=predictions_path,
        output_path=output_path,
    )

    assert output_path.is_file()
    assert json.loads(output_path.read_text(encoding="utf-8")) == report
    assert report["protocol"] == "forward"
    assert report["row_count"] == 16
    assert len(report["basin_metrics"]) == 8
    assert set(report["basin_metrics"].values()) == {1.0}


@pytest.mark.parametrize("mutation", ["missing", "extra_date", "wrong_basin", "duplicate"])
def test_external_development_scorer_rejects_prediction_key_mismatch(tmp_path, mutation):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    package_root = _build_packages(tmp_path)
    truth = pd.read_parquet(package_root / "forward" / "score" / "validation_truth.parquet")
    predictions = truth.rename(columns={"qobs": "qsim"})
    if mutation == "missing":
        predictions = predictions.iloc[1:].copy()
    elif mutation == "extra_date":
        extra = predictions.iloc[[0]].copy()
        extra["date"] = pd.Timestamp("2007-01-01")
        predictions = pd.concat([predictions, extra], ignore_index=True)
    elif mutation == "wrong_basin":
        predictions.loc[0, "basin"] = "99999999"
    elif mutation == "duplicate":
        predictions = pd.concat([predictions, predictions.iloc[[0]]], ignore_index=True)
    predictions_path = tmp_path / "predictions.parquet"
    predictions.to_parquet(predictions_path, index=False)
    output_path = tmp_path / "development-score.json"

    with pytest.raises(ValueError, match="prediction rows must exactly match development truth"):
        _score(
            package_root=package_root,
            protocol_name="forward",
            predictions_path=predictions_path,
            output_path=output_path,
        )

    assert not output_path.exists()


def test_external_development_scorer_rejects_nonfinite_predictions(tmp_path):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    package_root = _build_packages(tmp_path)
    truth = pd.read_parquet(package_root / "forward" / "score" / "validation_truth.parquet")
    predictions = truth.rename(columns={"qobs": "qsim"})
    predictions.loc[0, "qsim"] = float("inf")
    predictions_path = tmp_path / "predictions.parquet"
    predictions.to_parquet(predictions_path, index=False)
    output_path = tmp_path / "development-score.json"

    with pytest.raises(ValueError, match="prediction values must be finite"):
        _score(
            package_root=package_root,
            protocol_name="forward",
            predictions_path=predictions_path,
            output_path=output_path,
        )

    assert not output_path.exists()


def test_external_development_scorer_rejects_zero_variance_truth(tmp_path):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    package_root = _build_packages(tmp_path)
    truth_path = package_root / "forward" / "score" / "validation_truth.parquet"
    truth = pd.read_parquet(truth_path)
    first_basin = truth["basin"].iloc[0]
    truth.loc[truth["basin"] == first_basin, "qobs"] = 1.0
    truth.to_parquet(truth_path, index=False)
    manifest_path = package_root / "PACKAGE_MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    relative = truth_path.relative_to(package_root).as_posix()
    manifest["files"][relative] = _sha256(truth_path)
    manifest_path.write_text(json.dumps(manifest, sort_keys=True), encoding="utf-8")
    predictions_path = tmp_path / "predictions.parquet"
    truth.rename(columns={"qobs": "qsim"}).to_parquet(predictions_path, index=False)
    output_path = tmp_path / "development-score.json"

    with pytest.raises(ValueError, match="development truth must have nonzero variance for every basin"):
        _score(
            package_root=package_root,
            protocol_name="forward",
            predictions_path=predictions_path,
            output_path=output_path,
        )

    assert not output_path.exists()


def test_external_development_scorer_rejects_tampered_package_file(tmp_path):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    package_root = _build_packages(tmp_path)
    truth = pd.read_parquet(package_root / "forward" / "score" / "validation_truth.parquet")
    predictions_path = tmp_path / "predictions.parquet"
    truth.rename(columns={"qobs": "qsim"}).to_parquet(predictions_path, index=False)
    tampered = package_root / "forward" / "predict" / "predict_features.parquet"
    with tampered.open("ab") as stream:
        stream.write(b"tampered")
    output_path = tmp_path / "development-score.json"

    with pytest.raises(ValueError, match="development package file set or hash mismatch"):
        _score(
            package_root=package_root,
            protocol_name="forward",
            predictions_path=predictions_path,
            output_path=output_path,
        )

    assert not output_path.exists()


def test_external_development_scorer_rejects_linked_predictions(tmp_path):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    package_root = _build_packages(tmp_path)
    truth = pd.read_parquet(package_root / "forward" / "score" / "validation_truth.parquet")
    predictions_path = tmp_path / "predictions.parquet"
    truth.rename(columns={"qobs": "qsim"}).to_parquet(predictions_path, index=False)
    os.link(predictions_path, tmp_path / "predictions-alias.parquet")

    with pytest.raises(ValueError, match="predictions must be an unlinked regular Parquet file"):
        _score(
            package_root=package_root,
            protocol_name="forward",
            predictions_path=predictions_path,
            output_path=tmp_path / "development-score.json",
        )


def test_external_development_scorer_rejects_symlinked_predictions(tmp_path):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    package_root = _build_packages(tmp_path)
    truth = pd.read_parquet(package_root / "forward" / "score" / "validation_truth.parquet")
    outside_path = tmp_path / "outside-predictions.parquet"
    truth.rename(columns={"qobs": "qsim"}).to_parquet(outside_path, index=False)
    predictions_path = tmp_path / "predictions.parquet"
    try:
        predictions_path.symlink_to(outside_path)
    except OSError as error:
        pytest.skip(f"symbolic links are unavailable: {error}")
    output_path = tmp_path / "development-score.json"

    with pytest.raises(ValueError, match="predictions must be an unlinked regular Parquet file"):
        _score(
            package_root=package_root,
            protocol_name="forward",
            predictions_path=predictions_path,
            output_path=output_path,
        )

    assert not output_path.exists()


def test_candidate_summary_rejects_symlinked_score_report(tmp_path):
    from unified_autoresearch.evaluation.scoring import summarize_candidate_development_scores

    package_root = _build_packages(tmp_path)
    score_paths = {}
    for protocol_name in ("forward", "reverse"):
        truth = pd.read_parquet(package_root / protocol_name / "score" / "validation_truth.parquet")
        predictions_path = tmp_path / f"{protocol_name}-predictions.parquet"
        truth.rename(columns={"qobs": "qsim"}).to_parquet(predictions_path, index=False)
        score_path = tmp_path / f"{protocol_name}-score.json"
        _score(
            package_root=package_root,
            protocol_name=protocol_name,
            predictions_path=predictions_path,
            output_path=score_path,
        )
        score_paths[protocol_name] = score_path

    linked_score = tmp_path / "forward-score-link.json"
    try:
        linked_score.symlink_to(score_paths["forward"])
    except OSError as error:
        pytest.skip(f"symbolic links are unavailable: {error}")
    score_paths["forward"] = linked_score
    output_path = tmp_path / "candidate-summary.json"

    with pytest.raises(ValueError, match="score reports must be unlinked regular files"):
        summarize_candidate_development_scores(
            candidate_id="reference-custom-python-v1",
            category="custom_python",
            registered_run_ids={
                "forward": "reference-custom-python-v1-forward-run",
                "reverse": "reference-custom-python-v1-reverse-run",
            },
            expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
            score_paths=score_paths,
            output_path=output_path,
        )

    assert not output_path.exists()


def test_external_development_scorer_rejects_boolean_predictions(tmp_path):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    package_root = _build_packages(tmp_path)
    truth = pd.read_parquet(package_root / "forward" / "score" / "validation_truth.parquet")
    predictions = truth.rename(columns={"qobs": "qsim"})
    predictions["qsim"] = True
    predictions_path = tmp_path / "predictions.parquet"
    predictions.to_parquet(predictions_path, index=False)

    with pytest.raises(ValueError, match="prediction values must be finite non-boolean numbers"):
        _score(
            package_root=package_root,
            protocol_name="forward",
            predictions_path=predictions_path,
            output_path=tmp_path / "development-score.json",
        )


def test_candidate_summary_combines_both_protocols_into_eight_cells(tmp_path):
    from unified_autoresearch.evaluation.scoring import (
        score_development_predictions,
        summarize_candidate_development_scores,
    )

    package_root = _build_packages(tmp_path)
    score_paths = {}
    for protocol_name in ("forward", "reverse"):
        truth = pd.read_parquet(package_root / protocol_name / "score" / "validation_truth.parquet")
        predictions_path = tmp_path / f"{protocol_name}-predictions.parquet"
        truth.rename(columns={"qobs": "qsim"}).to_parquet(predictions_path, index=False)
        score_path = tmp_path / f"{protocol_name}-score.json"
        _score(
            package_root=package_root,
            protocol_name=protocol_name,
            predictions_path=predictions_path,
            output_path=score_path,
        )
        score_paths[protocol_name] = score_path

    summary = summarize_candidate_development_scores(
        candidate_id="reference-custom-python-v1",
        category="custom_python",
        registered_run_ids={
            "forward": "reference-custom-python-v1-forward-run",
            "reverse": "reference-custom-python-v1-reverse-run",
        },
        expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
        score_paths=score_paths,
        output_path=tmp_path / "candidate-summary.json",
    )

    assert summary["cell_count"] == 8
    assert len(summary["cells"]) == 8
    assert {cell["basin"] for cell in summary["cells"]} == set(
        json.loads((MODULE_ROOT / "selection" / "development_basins_v1.json").read_text(encoding="utf-8"))["basins"]
    )
    assert all(
        cell["forward_nse"] == cell["reverse_nse"] == cell["mean_nse"] == 1.0 for cell in summary["cells"]
    )


def test_scorer_rejects_package_manifest_that_differs_from_frozen_digest(tmp_path):
    from unified_autoresearch.evaluation.scoring import score_development_predictions

    package_root = _build_packages(tmp_path)
    manifest_path = package_root / "PACKAGE_MANIFEST.json"
    expected_manifest_sha256 = _sha256(manifest_path)
    truth = pd.read_parquet(package_root / "forward" / "score" / "validation_truth.parquet")
    predictions_path = tmp_path / "predictions.parquet"
    truth.rename(columns={"qobs": "qsim"}).to_parquet(predictions_path, index=False)
    with manifest_path.open("a", encoding="utf-8") as stream:
        stream.write(" ")
    output_path = tmp_path / "development-score.json"

    with pytest.raises(ValueError, match="development package manifest differs from the frozen digest"):
        score_development_predictions(
            package_root=package_root,
            expected_package_manifest_sha256=expected_manifest_sha256,
            candidate_id="reference-custom-python-v1",
            category="custom_python",
            registered_run_id="registered-run-forward-v1",
            protocol_name="forward",
            predictions_path=predictions_path,
            output_path=output_path,
        )

    assert not output_path.exists()


@pytest.mark.parametrize(
    "mutation",
    ["candidate_id", "category", "registered_run_id", "package_digest", "extra_field", "missing_row_count"],
)
def test_candidate_summary_rejects_report_identity_or_source_mismatch(tmp_path, mutation):
    from unified_autoresearch.evaluation.scoring import summarize_candidate_development_scores

    package_root = _build_packages(tmp_path)
    score_paths = {}
    for protocol_name in ("forward", "reverse"):
        truth = pd.read_parquet(package_root / protocol_name / "score" / "validation_truth.parquet")
        predictions_path = tmp_path / f"{protocol_name}-predictions.parquet"
        truth.rename(columns={"qobs": "qsim"}).to_parquet(predictions_path, index=False)
        score_path = tmp_path / f"{protocol_name}-score.json"
        _score(package_root, protocol_name, predictions_path, score_path)
        score_paths[protocol_name] = score_path
    reverse = json.loads(score_paths["reverse"].read_text(encoding="utf-8"))
    if mutation == "candidate_id":
        reverse["candidate_id"] = "different-candidate"
    elif mutation == "category":
        reverse["category"] = "deep_learning"
    elif mutation == "registered_run_id":
        reverse["registered_run_id"] = "different-run"
    elif mutation == "package_digest":
        reverse["package_manifest_sha256"] = "0" * 64
    elif mutation == "extra_field":
        reverse["unapproved"] = True
    elif mutation == "missing_row_count":
        del reverse["row_count"]
    modified_reverse_path = tmp_path / "reverse-score-modified.json"
    modified_reverse_path.write_text(json.dumps(reverse, allow_nan=False), encoding="utf-8")
    score_paths["reverse"] = modified_reverse_path
    output_path = tmp_path / "candidate-summary.json"

    with pytest.raises(ValueError, match="development score report identity or source mismatch"):
        summarize_candidate_development_scores(
            candidate_id="reference-custom-python-v1",
            category="custom_python",
            registered_run_ids={
                "forward": "reference-custom-python-v1-forward-run",
                "reverse": "reference-custom-python-v1-reverse-run",
            },
            expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
            score_paths=score_paths,
            output_path=output_path,
        )

    assert not output_path.exists()


def test_candidate_summary_averages_extreme_finite_metrics_without_partial_output(tmp_path):
    from unified_autoresearch.evaluation.scoring import summarize_candidate_development_scores

    package_root = _build_packages(tmp_path)
    score_paths = {}
    for protocol_name in ("forward", "reverse"):
        truth = pd.read_parquet(package_root / protocol_name / "score" / "validation_truth.parquet")
        predictions_path = tmp_path / f"{protocol_name}-predictions.parquet"
        truth.rename(columns={"qobs": "qsim"}).to_parquet(predictions_path, index=False)
        score_path = tmp_path / f"{protocol_name}-score.json"
        _score(package_root, protocol_name, predictions_path, score_path)
        score = json.loads(score_path.read_text(encoding="utf-8"))
        score["basin_metrics"] = {basin: -1e308 for basin in score["basin_metrics"]}
        extreme_score_path = tmp_path / f"{protocol_name}-score-extreme.json"
        extreme_score_path.write_text(json.dumps(score, allow_nan=False), encoding="utf-8")
        score_paths[protocol_name] = extreme_score_path
    output_path = tmp_path / "candidate-summary.json"

    summary = summarize_candidate_development_scores(
        candidate_id="reference-custom-python-v1",
        category="custom_python",
        registered_run_ids={
            "forward": "reference-custom-python-v1-forward-run",
            "reverse": "reference-custom-python-v1-reverse-run",
        },
        expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
        score_paths=score_paths,
        output_path=output_path,
    )

    assert output_path.is_file()
    assert json.loads(output_path.read_text(encoding="utf-8")) == summary
    assert all(cell["mean_nse"] == -1e308 for cell in summary["cells"])
