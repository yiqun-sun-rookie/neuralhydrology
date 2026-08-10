import json
import math
import os
import subprocess
from pathlib import Path

import pandas as pd
import pytest


EXPECTED_FAMILIES = {
    "deep_learning": "multilayer_perceptron",
    "conceptual_rainfall_runoff": "linear_reservoir",
    "fusion": "reservoir_regression_fusion",
    "custom_python": "per_basin_mean",
}


def _write_candidate_inputs(root: Path) -> None:
    root.mkdir()
    feature_rows = []
    target_rows = []
    for basin_index, basin in enumerate(("01013500", "02038850")):
        for day in range(4):
            feature_rows.append(
                {
                    "basin": basin,
                    "date": pd.Timestamp("2001-01-01") + pd.Timedelta(days=day),
                    "prcp": float(day + 1 + basin_index),
                    "tmin": float(2 + day),
                    "tmax": float(7 + day),
                    "srad": float(100 + 5 * day),
                    "vp": float(800 + 10 * basin_index + day),
                }
            )
            target_rows.append(
                {
                    "basin": basin,
                    "date": pd.Timestamp("2001-01-01") + pd.Timedelta(days=day),
                    "qobs": float(1.5 + basin_index + day * 0.75),
                }
            )
    prediction_rows = []
    for basin_index, basin in enumerate(("01013500", "02038850")):
        for day in range(2):
            prediction_rows.append(
                {
                    "basin": basin,
                    "date": pd.Timestamp("2001-01-05") + pd.Timedelta(days=day),
                    "prcp": float(2 + day + basin_index),
                    "tmin": float(6 + day),
                    "tmax": float(11 + day),
                    "srad": float(120 + 5 * day),
                    "vp": float(810 + 10 * basin_index + day),
                }
            )
    pd.DataFrame(feature_rows).to_parquet(root / "train_features.parquet", index=False)
    pd.DataFrame(target_rows).to_parquet(root / "train_targets.parquet", index=False)
    pd.DataFrame(prediction_rows).to_parquet(root / "predict_features.parquet", index=False)
    (root / "static_attributes.json").write_text(
        json.dumps(
            {
                "schema_version": "development_static_attributes_v1",
                "basins": {
                    "01013500": {"attribute_a": 1.0, "attribute_b": 2.0},
                    "02038850": {"attribute_a": 3.0, "attribute_b": 4.0},
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def _initialize_repo(repo: Path) -> None:
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo, check=True)
    (repo / ".gitignore").write_text("runs/\n", encoding="utf-8")
    (repo / "configuration.json").write_text("{}\n", encoding="utf-8")
    (repo / "data-manifest.json").write_text(
        '{"kind":"synthetic development candidate contract"}\n', encoding="utf-8"
    )


@pytest.mark.parametrize("category", sorted(EXPECTED_FAMILIES))
def test_reference_candidate_catalog_materializes_exact_category(category, tmp_path):
    from unified_autoresearch.candidates.catalog import materialize_reference_candidate

    materialized = materialize_reference_candidate(category=category, output_root=tmp_path / category)

    assert materialized.descriptor.category == category
    assert materialized.descriptor.candidate_id == f"reference-{category.replace('_', '-')}-v1"
    assert materialized.source_root == (tmp_path / category).resolve()
    assert materialized.descriptor_path == materialized.source_root / "candidate-descriptor.json"
    assert {path.name for path in materialized.source_root.iterdir()} == {
        "candidate-descriptor.json",
        "entrypoint.py",
        "method.py",
        "runtime_common.py",
    }


@pytest.mark.skipif(os.name != "nt", reason="Windows extended-length paths are Windows-specific")
def test_reference_candidate_source_copy_supports_a_path_longer_than_260_characters(tmp_path):
    from unified_autoresearch.candidates.catalog import _copy_file_long_path_safe

    source_root = tmp_path / "long_candidate_source"
    while len(str(source_root / "method.py")) <= 270:
        source_root /= "nested_candidate_source_segment"
    extended_source_root = "\\\\?\\" + str(source_root.resolve())
    os.makedirs(extended_source_root)
    source = source_root / "method.py"
    source_bytes = b"METHOD_FAMILY = 'long_path_probe'\n"
    with open("\\\\?\\" + str(source.resolve()), "xb") as stream:
        stream.write(source_bytes)
    destination = tmp_path / "copied-method.py"

    _copy_file_long_path_safe(source, destination)

    assert destination.read_bytes() == source_bytes


@pytest.mark.parametrize("category", sorted(EXPECTED_FAMILIES))
def test_each_reference_candidate_trains_and_predicts_through_registered_runtime(
    category, tmp_path, frozen_dependencies_for_active_environment
):
    from unified_autoresearch.candidates.catalog import materialize_reference_candidate
    from unified_autoresearch.registry.store import Registry
    from unified_autoresearch.runtime.layout import create_run_layout
    from unified_autoresearch.runtime.orchestrator import run_registered_candidate
    from unified_autoresearch.runtime.resources import ResourceSnapshot

    repo = tmp_path / "repo"
    _initialize_repo(repo)
    materialized = materialize_reference_candidate(
        category=category,
        output_root=repo / "candidate-source",
        dependencies=frozen_dependencies_for_active_environment,
    )
    inputs = repo / "synthetic-development-inputs"
    _write_candidate_inputs(inputs)
    (repo / "requirements.txt").write_text(
        "\n".join(materialized.descriptor.dependencies) + "\n", encoding="utf-8"
    )
    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "synthetic candidate fixture"], cwd=repo, check=True)

    snapshot = ResourceSnapshot(
        available_cpu_cores=4,
        available_gpu_count=0,
        available_memory_gb=4.0,
        free_disk_gb=10.0,
    )
    train_run_id = f"{category}-train"
    train_layout = create_run_layout(
        repo / "runs" / train_run_id,
        descriptor=materialized.descriptor,
        candidate_source_root=materialized.source_root,
        mode="train",
        input_sources={
            "train_features.parquet": inputs / "train_features.parquet",
            "train_targets.parquet": inputs / "train_targets.parquet",
            "static_attributes.json": inputs / "static_attributes.json",
        },
    )
    train_result = run_registered_candidate(
        repo_root=repo,
        descriptor=materialized.descriptor,
        layout=train_layout,
        mode="train",
        run_id=train_run_id,
        code_paths=[materialized.source_root],
        configuration_paths=[repo / "configuration.json", materialized.descriptor_path],
        dependency_paths=[repo / "requirements.txt"],
        data_manifest_paths=[repo / "data-manifest.json"],
        resource_snapshot=snapshot,
    )
    assert train_result.runtime_result.status == "succeeded"
    assert train_result.runtime_result.denied_event_count == 0
    model_path = train_layout.output_root / "model_artifacts" / "model.json"
    model = json.loads(model_path.read_text(encoding="utf-8"))
    assert model["method_family"] == EXPECTED_FAMILIES[category]

    predict_run_id = f"{category}-predict"
    predict_layout = create_run_layout(
        repo / "runs" / predict_run_id,
        descriptor=materialized.descriptor,
        candidate_source_root=materialized.source_root,
        mode="predict",
        input_sources={
            "predict_features.parquet": inputs / "predict_features.parquet",
            "static_attributes.json": inputs / "static_attributes.json",
            "model_artifacts": train_layout.output_root / "model_artifacts",
        },
    )
    predict_result = run_registered_candidate(
        repo_root=repo,
        descriptor=materialized.descriptor,
        layout=predict_layout,
        mode="predict",
        run_id=predict_run_id,
        code_paths=[materialized.source_root],
        configuration_paths=[repo / "configuration.json", materialized.descriptor_path],
        dependency_paths=[repo / "requirements.txt"],
        data_manifest_paths=[repo / "data-manifest.json"],
        resource_snapshot=snapshot,
    )
    assert predict_result.runtime_result.status == "succeeded"
    assert predict_result.runtime_result.denied_event_count == 0
    predictions = pd.read_parquet(predict_layout.output_root / "predictions.parquet")
    assert set(predictions.columns) == {"basin", "date", "qsim"}
    assert len(predictions) == 4
    assert all(math.isfinite(value) for value in predictions["qsim"])

    for run_id, result in ((train_run_id, train_result), (predict_run_id, predict_result)):
        registry = Registry(
            result.registry_path,
            scheduler_lock_path=result.scheduler_lock_path,
            receipt_dir=result.receipt_dir,
        )
        assert registry.current_state(run_id) == "succeeded"
        assert registry.verify() == {"record_count": 8, "failure_count": 0, "failures": []}
