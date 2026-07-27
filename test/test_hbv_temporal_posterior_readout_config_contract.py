"""Frozen contract for the temporal-posterior confirmation."""

from __future__ import annotations

import csv
import hashlib
import importlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
EXPERIMENT_ID = "g3_temporal_posterior_readout_param_switch_v01"
CONFIG_PATH = (
    REPO_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / f"{EXPERIMENT_ID}.json"
)
CONFIG_DIRECTORY = CONFIG_PATH.parent
REGISTRY_PATH = CONFIG_DIRECTORY / "g3_experiment_registry.csv"
RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_temporal_posterior_readout"
)


def _load_config() -> dict:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def _sha256(relative_path: str) -> str:
    return hashlib.sha256((REPO_ROOT / relative_path).read_bytes()).hexdigest()


def test_actual_config_matches_the_frozen_runner_contract():
    runner = importlib.import_module(RUNNER_MODULE)
    config = _load_config()

    runner._validate_config_contract(config)
    blocks = runner._generated_blocks(config)
    assert len(blocks) == 96
    assert blocks[0] == {
        "block_id": "g3_temporal_confirmation_block_001",
        "forcing_seed": 7411001,
        "process_noise_seed": 7412001,
        "observation_noise_seed": 7413001,
    }
    assert blocks[-1] == {
        "block_id": "g3_temporal_confirmation_block_096",
        "forcing_seed": 7411096,
        "process_noise_seed": 7412096,
        "observation_noise_seed": 7413096,
    }


def test_seed_families_are_disjoint_and_unused_by_other_configs():
    runner = importlib.import_module(RUNNER_MODULE)
    config = _load_config()
    blocks = runner._generated_blocks(config)
    seeds = {
        int(block[key])
        for block in blocks
        for key in (
            "forcing_seed",
            "process_noise_seed",
            "observation_noise_seed",
        )
    }
    seeds.add(int(config["bootstrap"]["seed"]))

    assert len(seeds) == 289
    collisions = []
    for path in CONFIG_DIRECTORY.glob("*.json"):
        if path == CONFIG_PATH:
            continue
        text = path.read_text(encoding="utf-8")
        for seed in seeds:
            if str(seed) in text:
                collisions.append((path.name, seed))
    assert collisions == []


def test_scientific_sources_and_resource_pilot_match_frozen_hashes():
    config = _load_config()

    for source_name in (
        "parameter_source",
        "process_noise_source",
        "observation_noise_source",
    ):
        source = config[source_name]
        assert _sha256(source["path"]) == source["sha256"]
    pilot = config["resource_pilot"]
    assert _sha256(pilot["source"]) == pilot["sha256"]
    assert config["forcing"] == {
        "warmup_days": 45,
        "reference_total_days": 592,
        "rain_shape": 0.8,
        "rain_scale": 4.0,
    }
    assert config["stage_lengths"] == [180, 180, 180]
    assert config["lead_days"] == [1, 3, 7]
    assert config["initial_covariance_fraction"] == 0.001
    assert config["factor_transition_stay_probability"] == 0.98


def test_contract_documents_and_protected_paths_exist():
    config = _load_config()

    assert (REPO_ROOT / config["design_doc"]).is_file()
    assert (REPO_ROOT / config["implementation_plan"]).is_file()
    protected = config["protected_paths"]
    assert len(protected) == len(set(protected))
    assert (
        "src/hbv_multilead_joint_uncertainty/configs/"
        f"{EXPERIMENT_ID}.json"
    ) in protected
    for relative_path in protected:
        assert (REPO_ROOT / relative_path).exists(), relative_path


def test_formal_output_is_complete_and_records_the_frozen_rejection():
    result_root = (
        REPO_ROOT / "results" / "23_hbv_multilead_joint_uncertainty"
    )
    output = result_root / EXPERIMENT_ID
    summary = json.loads(
        (output / "summary.json").read_text(encoding="utf-8")
    )
    assert output.is_dir()
    assert not (result_root / f"{EXPERIMENT_ID}.incomplete").exists()
    assert (
        result_root / f"{EXPERIMENT_ID}.preregistered.json"
    ).is_file()
    assert summary["integrity_status"] == "passed"
    assert summary["retention_decision"] == "reject"
    assert summary["result"]["selection_accuracy"] == 282 / 288
    assert summary["result"]["retention_gates"] == {
        "one_day_exact": True,
        "selection_accuracy": True,
        "three_day_no_material_harm_vs_full": False,
        "seven_day_material_improvement_vs_full": False,
        "three_day_no_material_harm_vs_none": False,
        "seven_day_material_improvement_vs_none": False,
        "retain": False,
    }


def test_registry_has_one_exact_completed_row():
    with REGISTRY_PATH.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    matching = [row for row in rows if row["exp_id"] == EXPERIMENT_ID]

    assert len(matching) == 1
    assert matching[0] == {
        "exp_id": EXPERIMENT_ID,
        "type": "independent temporal posterior confirmation",
        "hypothesis": (
            "Thirty-day mean posterior selection improves seven-day "
            "forecasts while preserving one-day forecasts"
        ),
        "base_config": f"{EXPERIMENT_ID}.json",
        "changed_factor": (
            "one-day final posterior weighting and three-day seven-day "
            "thirty-day mean posterior selection"
        ),
        "fixed_factors": (
            "candidate filters full interaction assimilation truth schedule "
            "noise levels and frozen forecast contract"
        ),
        "seeds": "7411001-7414001",
        "status": "completed",
        "run_dir": (
            "results/23_hbv_multilead_joint_uncertainty/"
            f"{EXPERIMENT_ID}"
        ),
        "best_checkpoint": "not applicable",
        "metrics_path": "summary.json",
        "paper_name": "G3 temporal posterior readout confirmation",
        "notes": (
            "Formal package and independent recomputation passed; selection "
            "accuracy was 97.92 percent but four forecast gates failed; "
            "rule rejected; no post-confirmation tuning"
        ),
    }
