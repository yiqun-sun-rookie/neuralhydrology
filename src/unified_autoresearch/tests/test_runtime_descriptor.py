import copy
import json
import os
from pathlib import Path

import pytest


def _valid_descriptor() -> dict:
    return {
        "schema_version": "candidate_descriptor_v1",
        "candidate_id": "candidate-001",
        "category": "custom_python",
        "entrypoint": {"train": "train.py", "predict": "predict.py"},
        "dependencies": ["example-dependency==1.2.3"],
        "allowed_reads": {
            "train": ["train_features.parquet", "train_targets.parquet", "static_attributes.json"],
            "predict": ["predict_features.parquet", "static_attributes.json", "model_artifacts"],
        },
        "outputs": {"train": ["model_artifacts"], "predict": ["predictions.parquet"]},
        "seed": 17,
        "resources": {
            "cpu_cores": 1,
            "gpu_count": 0,
            "estimated_peak_memory_gb": 1.0,
            "memory_safety_reserve_gb": 0.5,
            "estimated_output_gb": 0.1,
            "disk_safety_reserve_gb": 0.5,
            "independent_monitor_enabled": False,
            "monitor_reason": "short deterministic contract test",
        },
        "checkpoint": {"supported": True, "staging_dir": "checkpoint_staging", "keep": "all"},
        "resume": {"supported": True},
    }


def _write_descriptor(root: Path, value: dict) -> Path:
    path = root / "candidate.json"
    path.write_text(json.dumps(value), encoding="utf-8")
    return path


def _load_valid_descriptor(tmp_path: Path):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor

    candidate_root = tmp_path / "candidate"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    (candidate_root / "predict.py").write_text("pass\n", encoding="utf-8")
    descriptor = load_and_validate_candidate_descriptor(
        _write_descriptor(tmp_path, _valid_descriptor()), candidate_root=candidate_root
    )
    return descriptor, candidate_root


def test_valid_candidate_descriptor_is_loaded_from_existing_entrypoints(tmp_path):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor

    candidate_root = tmp_path / "candidate"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    (candidate_root / "predict.py").write_text("pass\n", encoding="utf-8")

    descriptor = load_and_validate_candidate_descriptor(
        _write_descriptor(tmp_path, _valid_descriptor()), candidate_root=candidate_root
    )

    assert descriptor.candidate_id == "candidate-001"
    assert descriptor.entrypoint["predict"] == "predict.py"


def test_candidate_descriptor_accepts_preserve_all_checkpoint_retention(tmp_path):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor

    candidate_root = tmp_path / "candidate"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    (candidate_root / "predict.py").write_text("pass\n", encoding="utf-8")
    changed = _valid_descriptor()
    changed["checkpoint"]["keep"] = "all"

    descriptor = load_and_validate_candidate_descriptor(
        _write_descriptor(tmp_path, changed), candidate_root=candidate_root
    )

    assert descriptor.checkpoint["keep"] == "all"


def test_candidate_descriptor_rejects_unknown_fields(tmp_path):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor

    candidate_root = tmp_path / "candidate"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    (candidate_root / "predict.py").write_text("pass\n", encoding="utf-8")
    changed = _valid_descriptor()
    changed["shell_command"] = "do-anything"

    with pytest.raises(ValueError, match="unknown candidate descriptor fields"):
        load_and_validate_candidate_descriptor(_write_descriptor(tmp_path, changed), candidate_root=candidate_root)


def test_candidate_descriptor_rejects_missing_command_entrypoint(tmp_path):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor

    candidate_root = tmp_path / "candidate"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    changed = _valid_descriptor()
    del changed["entrypoint"]["predict"]

    with pytest.raises(ValueError, match="entrypoint commands must be exactly train and predict"):
        load_and_validate_candidate_descriptor(_write_descriptor(tmp_path, changed), candidate_root=candidate_root)


def test_candidate_descriptor_rejects_non_exact_dependency_versions(tmp_path):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor

    candidate_root = tmp_path / "candidate"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    (candidate_root / "predict.py").write_text("pass\n", encoding="utf-8")
    changed = _valid_descriptor()
    changed["dependencies"] = ["example-dependency>=1.2"]

    with pytest.raises(ValueError, match="dependency must pin one exact version"):
        load_and_validate_candidate_descriptor(_write_descriptor(tmp_path, changed), candidate_root=candidate_root)


def test_candidate_descriptor_rejects_paths_outside_candidate_root(tmp_path):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor

    candidate_root = tmp_path / "candidate"
    candidate_root.mkdir()
    (candidate_root / "predict.py").write_text("pass\n", encoding="utf-8")
    (tmp_path / "outside.py").write_text("pass\n", encoding="utf-8")
    changed = _valid_descriptor()
    changed["entrypoint"]["train"] = "../outside.py"

    with pytest.raises(ValueError, match="entrypoint must be a safe relative path"):
        load_and_validate_candidate_descriptor(_write_descriptor(tmp_path, changed), candidate_root=candidate_root)


def test_candidate_descriptor_rejects_prediction_truth_and_output_drift(tmp_path):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor

    candidate_root = tmp_path / "candidate"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    (candidate_root / "predict.py").write_text("pass\n", encoding="utf-8")
    changed = copy.deepcopy(_valid_descriptor())
    changed["allowed_reads"]["predict"].append("validation_truth.parquet")

    with pytest.raises(ValueError, match="prediction reads do not match the frozen contract"):
        load_and_validate_candidate_descriptor(_write_descriptor(tmp_path, changed), candidate_root=candidate_root)


def test_run_layout_copies_only_exact_prediction_inputs_into_new_root(tmp_path):
    from unified_autoresearch.runtime.layout import create_run_layout

    descriptor, candidate_root = _load_valid_descriptor(tmp_path)
    sources = tmp_path / "sources"
    sources.mkdir()
    (sources / "predict_features.parquet").write_bytes(b"features")
    (sources / "static_attributes.json").write_text("{}\n", encoding="utf-8")
    (sources / "model_artifacts").mkdir()
    (sources / "model_artifacts" / "model.bin").write_bytes(b"model")

    layout = create_run_layout(
        tmp_path / "run",
        descriptor=descriptor,
        candidate_source_root=candidate_root,
        mode="predict",
        input_sources={name: sources / name for name in descriptor.allowed_reads["predict"]},
    )

    assert (layout.candidate_root / "predict.py").is_file()
    assert (layout.input_root / "predict_features.parquet").read_bytes() == b"features"
    assert (layout.input_root / "model_artifacts" / "model.bin").read_bytes() == b"model"
    assert not (layout.input_root / "validation_truth.parquet").exists()
    assert layout.output_root.is_dir()
    assert layout.checkpoint_staging_root.is_dir()
    assert layout.checkpoints_root.is_dir()
    assert layout.log_root.is_dir()
    stored_descriptor = json.loads(layout.descriptor_path.read_text(encoding="utf-8"))
    assert stored_descriptor["candidate_id"] == descriptor.candidate_id
    assert stored_descriptor["entrypoint"] == descriptor.entrypoint
    assert stored_descriptor["resources"] == descriptor.resources


def test_run_layout_refuses_existing_root(tmp_path):
    from unified_autoresearch.runtime.layout import create_run_layout

    descriptor, candidate_root = _load_valid_descriptor(tmp_path)
    run_root = tmp_path / "run"
    run_root.mkdir()

    with pytest.raises(FileExistsError, match="run root already exists"):
        create_run_layout(
            run_root,
            descriptor=descriptor,
            candidate_source_root=candidate_root,
            mode="predict",
            input_sources={},
        )


def test_run_layout_rejects_extra_prediction_truth_before_creating_root(tmp_path):
    from unified_autoresearch.runtime.layout import create_run_layout

    descriptor, candidate_root = _load_valid_descriptor(tmp_path)
    truth = tmp_path / "validation_truth.parquet"
    truth.write_bytes(b"forbidden")
    run_root = tmp_path / "run"

    with pytest.raises(ValueError, match="input sources must exactly match declared reads"):
        create_run_layout(
            run_root,
            descriptor=descriptor,
            candidate_source_root=candidate_root,
            mode="predict",
            input_sources={"validation_truth.parquet": truth},
        )
    assert not run_root.exists()


@pytest.mark.parametrize(
    ("field_path", "replacement"),
    [
        (("candidate_id",), "../candidate"),
        (("category",), "unapproved-category"),
        (("seed",), -1),
        (("resources", "cpu_cores"), 0),
        (("checkpoint", "keep"), 2),
        (("resume", "supported"), False),
    ],
    ids=("candidate-id", "category", "seed", "resources", "checkpoint", "resume"),
)
def test_candidate_descriptor_rejects_invalid_runtime_declarations(tmp_path, field_path, replacement):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor

    candidate_root = tmp_path / "candidate"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    (candidate_root / "predict.py").write_text("pass\n", encoding="utf-8")
    changed = copy.deepcopy(_valid_descriptor())
    target = changed
    for key in field_path[:-1]:
        target = target[key]
    target[field_path[-1]] = replacement

    with pytest.raises(ValueError, match="candidate descriptor runtime declaration is invalid"):
        load_and_validate_candidate_descriptor(_write_descriptor(tmp_path, changed), candidate_root=candidate_root)


def test_run_layout_rejects_hardlinked_input_before_copying_it_into_allowlist(tmp_path):
    from unified_autoresearch.runtime.layout import create_run_layout

    descriptor, candidate_root = _load_valid_descriptor(tmp_path)
    sources = tmp_path / "sources"
    sources.mkdir()
    (sources / "predict_features.parquet").write_bytes(b"features")
    (sources / "static_attributes.json").write_text("{}\n", encoding="utf-8")
    artifacts = sources / "model_artifacts"
    artifacts.mkdir()
    outside = tmp_path / "outside-secret.bin"
    outside.write_bytes(b"must-not-enter-input-root")
    os.link(outside, artifacts / "linked-secret.bin")
    run_root = tmp_path / "run"

    with pytest.raises(ValueError, match="linked input or candidate file is forbidden"):
        create_run_layout(
            run_root,
            descriptor=descriptor,
            candidate_source_root=candidate_root,
            mode="predict",
            input_sources={name: sources / name for name in descriptor.allowed_reads["predict"]},
        )

    assert not run_root.exists()


def test_run_layout_rejects_symlinked_directory_used_as_declared_input(tmp_path):
    from unified_autoresearch.runtime.layout import create_run_layout

    descriptor, candidate_root = _load_valid_descriptor(tmp_path)
    sources = tmp_path / "sources"
    sources.mkdir()
    (sources / "predict_features.parquet").write_bytes(b"features")
    (sources / "static_attributes.json").write_text("{}\n", encoding="utf-8")
    outside = tmp_path / "outside-artifacts"
    outside.mkdir()
    (outside / "secret.bin").write_bytes(b"must-not-enter-input-root")
    try:
        (sources / "model_artifacts").symlink_to(outside, target_is_directory=True)
    except OSError as error:
        pytest.skip(f"symbolic links are unavailable: {error}")
    run_root = tmp_path / "run"

    with pytest.raises(ValueError, match="linked input or candidate file is forbidden"):
        create_run_layout(
            run_root,
            descriptor=descriptor,
            candidate_source_root=candidate_root,
            mode="predict",
            input_sources={name: sources / name for name in descriptor.allowed_reads["predict"]},
        )

    assert not run_root.exists()


def test_run_layout_rejects_symlinked_candidate_source_root(tmp_path):
    from unified_autoresearch.runtime.layout import create_run_layout

    descriptor, candidate_root = _load_valid_descriptor(tmp_path)
    sources = tmp_path / "sources"
    sources.mkdir()
    (sources / "predict_features.parquet").write_bytes(b"features")
    (sources / "static_attributes.json").write_text("{}\n", encoding="utf-8")
    (sources / "model_artifacts").mkdir()
    linked_candidate = tmp_path / "linked-candidate"
    try:
        linked_candidate.symlink_to(candidate_root, target_is_directory=True)
    except OSError as error:
        pytest.skip(f"symbolic links are unavailable: {error}")
    run_root = tmp_path / "run"

    with pytest.raises(ValueError, match="linked input or candidate file is forbidden"):
        create_run_layout(
            run_root,
            descriptor=descriptor,
            candidate_source_root=linked_candidate,
            mode="predict",
            input_sources={name: sources / name for name in descriptor.allowed_reads["predict"]},
        )

    assert not run_root.exists()


def test_run_layout_rejects_symlink_used_as_declared_input_root(tmp_path):
    from unified_autoresearch.runtime.layout import create_run_layout

    descriptor, candidate_root = _load_valid_descriptor(tmp_path)
    sources = tmp_path / "sources"
    sources.mkdir()
    outside = tmp_path / "outside-features.parquet"
    outside.write_bytes(b"must-not-follow")
    linked_features = sources / "predict_features.parquet"
    try:
        linked_features.symlink_to(outside)
    except OSError as error:
        pytest.skip(f"symbolic links are unavailable: {error}")
    (sources / "static_attributes.json").write_text("{}\n", encoding="utf-8")
    (sources / "model_artifacts").mkdir()
    run_root = tmp_path / "run"

    with pytest.raises(ValueError, match="linked input or candidate file is forbidden"):
        create_run_layout(
            run_root,
            descriptor=descriptor,
            candidate_source_root=candidate_root,
            mode="predict",
            input_sources={name: sources / name for name in descriptor.allowed_reads["predict"]},
        )

    assert not run_root.exists()
