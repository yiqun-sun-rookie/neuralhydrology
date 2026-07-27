import csv
import hashlib
import json
from pathlib import Path


IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG_ROOT = IDEA_ROOT / "configs"
REPO_ROOT = IDEA_ROOT.parents[1]
FROZEN_BASIN_SHA256 = "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65"
FROZEN_TARGET_SHA256 = "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c"


def _load(name: str) -> dict:
    return json.loads((CONFIG_ROOT / name).read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_v06_diagnostic_configs_freeze_identity_inputs_dates_and_output_roots():
    mask = _load("diagnostic_mask_v06.json")
    nesting = _load("strict_nesting_v06.json")

    assert mask["experiment_id"] == "D06-MASK"
    assert nesting["experiment_id"] == "R06-NEST"
    assert mask["experiment_family"] != nesting["experiment_family"]
    assert mask["basin_file_sha256"] == nesting["basin_file_sha256"] == FROZEN_BASIN_SHA256
    assert mask["target_bundle_sha256"] == nesting["target_bundle_sha256"] == FROZEN_TARGET_SHA256
    assert mask["validation_start"] == nesting["validation_start"] == "2006-10-01"
    assert mask["validation_end"] == nesting["validation_end"] == "2008-09-30"
    assert mask["results_root"] != nesting["results_root"]
    assert all(f"_v0{version}" not in mask["results_root"] for version in (3, 4, 5))
    assert all(f"_v0{version}" not in nesting["results_root"] for version in (3, 4, 5))
    assert nesting["reproduction_tolerance"] == {
        "absolute": 0.0,
        "relative": 0.0,
    }
    assert nesting["candidate_iteration_budget"] == 5
    source_run = REPO_ROOT / mask["source_run_dir"]
    assert _sha256(source_run / "checkpoint.pt") == mask["source_checkpoint_sha256"]
    assert _sha256(source_run / "predictions.csv") == mask["source_predictions_sha256"]


def test_v06_registry_has_one_unique_row_for_each_diagnostic():
    with (IDEA_ROOT / "registry.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))

    by_id = {}
    for row in rows:
        by_id.setdefault(row["exp_id"], []).append(row)
    assert len(by_id["D06-MASK"]) == 1
    assert len(by_id["R06-NEST"]) == 1
    assert by_id["D06-MASK"][0]["run_dir"].endswith("strict_branch_masking_v06")
    assert by_id["R06-NEST"][0]["run_dir"].endswith("strict_nesting_v06")
