import csv
import hashlib
import json
from pathlib import Path


IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG_ROOT = IDEA_ROOT / "configs"
REPO_ROOT = IDEA_ROOT.parents[1]


def _load(name: str) -> dict:
    return json.loads((CONFIG_ROOT / name).read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_v07_configs_freeze_sequential_state_transfer_protocol():
    pilot = _load("sequential_transfer_s01_v07.json")
    smoke = _load("sequential_transfer_s01_smoke_v07.json")

    for config in (pilot, smoke):
        assert config["experiment_id"] == "E07-S01"
        assert config["experiment_family"] == "sequential_coarse_to_fine_v07"
        assert config["basin_file_sha256"] == (
            "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65"
        )
        assert config["target_bundle_sha256"] == (
            "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c"
        )
        assert config["recent_lags"] == [0, 269]
        assert config["medium_lags"] == [270, 1824]
        assert config["old_lags"] == [1825, 3649]
        assert config["medium_bins"] == config["old_bins"] == 60
        assert config["recent_hidden_size"] == 256
        assert config["medium_hidden_size"] == 256
        assert config["old_hidden_size"] == 256
        assert config["candidate_parameter_count"] == 891_137
        assert config["capacity_control_parameter_count"] == 890_436
        assert config["stage1_seed"] == 100
        assert config["conditional_seeds"] == [200, 300]
        assert config["stage1_gates"] == {
            "median_delta_classic_at_least": 0.01,
            "median_delta_capacity_above": 0.0,
            "median_delta_late_concat_above": 0.0,
            "win_fraction_classic_at_least": 0.55,
        }
        assert config["formal_evaluation_access"] is False
        assert _sha256(
            REPO_ROOT / "results/26_historical_band_experts/strict_nesting_v06/summary.json"
        ) == config["strict_nesting_summary_sha256"]
        assert _sha256(
            REPO_ROOT / config["legacy_late_concat_predictions"]
        ) == config["legacy_late_concat_predictions_sha256"]

    assert pilot["mode"] == "pilot"
    assert pilot["epochs"] == 30
    assert pilot["limit_batches"] == 0
    assert pilot["limit_validation_samples"] == 0
    assert pilot["results_root"].endswith("sequential_coarse_to_fine_v07")
    assert smoke["mode"] == "smoke"
    assert smoke["epochs"] == 2
    assert smoke["limit_batches"] == 2
    assert smoke["limit_validation_samples"] == 1024
    assert smoke["results_root"].endswith("sequential_coarse_to_fine_v07_smoke")


def test_v07_registry_has_one_preregistered_sequential_transfer_row():
    with (IDEA_ROOT / "registry.csv").open(encoding="utf-8", newline="") as handle:
        rows = [row for row in csv.DictReader(handle) if row["exp_id"] == "E07-S01"]

    assert len(rows) == 1
    assert rows[0]["status"] == "preregistered"
    assert rows[0]["base_config"] == "configs/sequential_transfer_s01_v07.json"
    assert rows[0]["run_dir"].endswith("sequential_coarse_to_fine_v07")
