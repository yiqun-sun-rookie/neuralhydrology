from __future__ import annotations

import importlib.util
from pathlib import Path

import numpy as np
import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = (
    PROJECT_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "scripts"
    / "run_g3_state_domain_consistent_parameter_switch_confirmation.py"
)


def _runner():
    specification = importlib.util.spec_from_file_location("parameter_switch_runner", RUNNER_PATH)
    module = importlib.util.module_from_spec(specification)
    assert specification.loader is not None
    specification.loader.exec_module(module)
    return module


def test_frozen_config_loads_and_has_expected_hash():
    runner = _runner()
    config = runner.load_and_validate_config()
    assert config["experiment_id"] == runner.EXPERIMENT_ID
    assert runner._sha256(runner.DEFAULT_CONFIG) == runner.CONFIG_SHA256


def test_changed_config_is_rejected(tmp_path):
    runner = _runner()
    changed = tmp_path / "changed.json"
    changed.write_text(runner.DEFAULT_CONFIG.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="frozen config hash mismatch"):
        runner.load_and_validate_config(changed)


def test_output_guard_rejects_any_existing_target(tmp_path, monkeypatch):
    runner = _runner()
    config = runner.load_and_validate_config()
    result = tmp_path / "result"
    visual = tmp_path / "visual"
    verification = tmp_path / "verification"
    monkeypatch.setattr(runner, "_result_paths", lambda _config: (result, visual, verification))
    runner.assert_output_paths_absent(config)
    visual.mkdir()
    with pytest.raises(FileExistsError, match="already exists"):
        runner.assert_output_paths_absent(config)


def test_forcing_generation_is_deterministic_and_seed_specific():
    runner = _runner()
    config = runner.load_and_validate_config()
    seeds = config["formal_confirmation_seeds"]["forcing"]
    first = runner.generate_forcing_blocks(config, seeds)
    second = runner.generate_forcing_blocks(config, seeds)
    construction = runner.generate_forcing_blocks(
        config, config["candidate_construction_seeds"]["forcing"]
    )
    assert np.array_equal(first, second)
    assert not np.array_equal(first, construction)
    assert first.shape == (8, 585, 3)
    one_block = runner.generate_forcing_blocks(config, seeds[:1])
    assert one_block.shape == (1, 585, 3)


def test_candidate_vectors_equal_frozen_source_transformation():
    runner = _runner()
    config = runner.load_and_validate_config()
    source = runner._verify_source(config, "parameter_source")
    vectors = runner._parameter_vectors_from_config(config, source)
    assert tuple(vectors) == (
        "candidate_1_shared_limits",
        "candidate_2_shared_limits",
        "candidate_3_shared_limits",
    )
    assert len({values["parFC"] for values in vectors.values()}) == 1
    assert len({values["parCWH"] for values in vectors.values()}) == 1


def test_seed_groups_are_unique_and_disjoint():
    runner = _runner()
    config = runner.load_and_validate_config()
    runner._validate_seed_contract(config)
    groups = [
        set(config["candidate_construction_seeds"]["forcing"]),
        *(set(values) for values in config["formal_confirmation_seeds"].values()),
    ]
    for left_index, left in enumerate(groups):
        for right in groups[left_index + 1 :]:
            assert left.isdisjoint(right)
