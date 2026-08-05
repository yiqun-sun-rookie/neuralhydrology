from __future__ import annotations

import ast
import copy
import json
from pathlib import Path

import pytest

from hbv_multilead_joint_uncertainty.scripts.run_g3_state_domain_consistent_process_noise_switch import (
    DEFAULT_CONFIG,
    assert_output_paths_absent,
    generate_forcing_blocks,
    load_and_validate_config,
    source_snapshot_entries,
)


def test_frozen_config_is_accepted_and_scientific_mutation_is_rejected(tmp_path):
    config = load_and_validate_config(DEFAULT_CONFIG)
    assert config["fixed_parameter_id"] == "trained_center"
    assert config["forbidden_scope"]["forecast_executed"] is False

    changed = copy.deepcopy(config)
    changed["process_noise_candidates"][2]["standard_deviation_mm_day"] = 15.0
    changed_path = tmp_path / "changed.json"
    changed_path.write_text(json.dumps(changed), encoding="utf-8")
    with pytest.raises(ValueError, match="frozen experiment contract"):
        load_and_validate_config(changed_path)


def test_output_paths_must_both_be_absent(tmp_path):
    result = tmp_path / "result"
    verification = tmp_path / "verification"
    assert_output_paths_absent(result, verification)
    result.mkdir()
    with pytest.raises(FileExistsError, match="result path already exists"):
        assert_output_paths_absent(result, verification)


def test_forcing_generation_is_deterministic_and_has_frozen_shape():
    config = load_and_validate_config(DEFAULT_CONFIG)
    first = generate_forcing_blocks(config)
    second = generate_forcing_blocks(config)
    assert first.shape == (8, 630, 3)
    assert (first == second).all()
    assert (first[:, :, 0] >= 5.0).all()
    assert (first[:, :, 1] == 2.0).all()
    assert (first[:, :, 2] == 10.0).all()


def test_runner_has_no_forecast_import():
    source_path = Path(__file__).resolve().parents[1] / (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "run_g3_state_domain_consistent_process_noise_switch.py"
    )
    tree = ast.parse(source_path.read_text(encoding="utf-8"))
    imported = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.append(node.module)
    assert not any("forecast" in name.lower() for name in imported)


def test_source_snapshot_uses_flat_short_names_for_windows_paths():
    entries = source_snapshot_entries()
    aliases = [alias for alias, _ in entries]
    sources = [source for _, source in entries]

    assert len(aliases) == len(set(aliases))
    assert len(sources) == len(set(sources))
    assert all(Path(alias).name == alias for alias in aliases)
    assert all(len(alias) <= 12 for alias in aliases)
