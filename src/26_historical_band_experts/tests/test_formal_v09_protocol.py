import csv
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG_ROOT = IDEA_ROOT / "configs"
REPO_ROOT = IDEA_ROOT.parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _read_json(name: str) -> dict:
    return json.loads((CONFIG_ROOT / name).read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_formal_v09_protocol_freezes_geometry_schedule_and_authorization():
    from formal_v09_protocol import (
        history_edges_v09,
        learning_rate_for_epoch_v09,
        load_protocol_v09,
        validate_protocol_v09,
    )

    config = load_protocol_v09(CONFIG_ROOT / "formal_v09_protocol.json")
    validate_protocol_v09(config)
    edges = history_edges_v09()
    edge_payload = json.dumps(edges.tolist(), separators=(",", ":")).encode("utf-8")

    assert config["protocol_id"] == "P09-FORMAL"
    assert config["basin_count"] == 531
    assert config["basin_file_sha256"] == (
        "cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85"
    )
    assert config["static_file_sha256"] == (
        "085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2"
    )
    assert config["dynamic_inputs"] == ["prcp", "tmin", "tmax", "srad", "vp"]
    assert config["known_forcing_data_issue"] == {
        "evidence_scope": "prior_read_only_audit_of_required_1980_2008_raw_maurer_rows",
        "condition": "tmin_equals_tmax_elementwise",
        "named_dynamic_columns": 5,
        "independent_dynamic_value_columns": 4,
        "handling": "preserve_frozen_named_columns_and_report_without_posthoc_repair",
    }
    assert "formal_evaluation_observed_discharge" in config["forbidden_inputs"]
    assert config["training_target_interface"]["bundle_generated"] is False
    assert config["train_period"] == ["1999-10-01", "2008-09-30"]
    assert config["evaluation_period"] == ["1989-10-01", "1999-09-30"]
    assert config["expected_training_samples"] == 1_745_928
    assert config["expected_evaluation_predictions"] == 1_939_212
    assert config["causal_window_days"] == 3_562
    assert config["recent_lags"] == [0, 269]
    assert config["history_lags"] == [270, 3_561]
    assert edges[0] == 270
    assert edges[-1] == 3_562
    assert tuple(np.diff(edges)[[np.argmin(np.diff(edges)), np.argmax(np.diff(edges))]]) == (6, 76)
    assert hashlib.sha256(edge_payload).hexdigest() == (
        "55bbdaf654e7ea2b8959cc5dd62de98e4631c272ffe9d7f4efeae9cb7240927b"
    )
    assert [learning_rate_for_epoch_v09(epoch) for epoch in (1, 10, 11, 20, 21, 30)] == [
        0.001,
        0.001,
        0.0005,
        0.0005,
        0.0001,
        0.0001,
    ]
    with pytest.raises(ValueError, match="1 through 30"):
        learning_rate_for_epoch_v09(0)
    assert config["authorization"] == {
        "protocol_implementation": True,
        "synthetic_tests": True,
        "formal_target_bundle_generation": False,
        "training": False,
        "formal_prediction_generation": False,
        "official_scoring": False,
    }


@pytest.mark.parametrize(
    ("name", "experiment_id", "variant"),
    [
        ("formal_v09_classic.json", "B09-CLASSIC", "classic_lstm_256_clean"),
        ("formal_v09_capacity.json", "B09-CAPACITY", "classic_lstm_369_capacity"),
        ("formal_v09_continuous.json", "E09-CONTINUOUS", "continuous_multiscale_history"),
    ],
)
def test_formal_v09_arm_configs_bind_one_protocol(name, experiment_id, variant):
    config = _read_json(name)

    assert config["experiment_id"] == experiment_id
    assert config["variant"] == variant
    assert config["protocol_sha256"] == _sha256(CONFIG_ROOT / "formal_v09_protocol.json")
    assert config["status"] == "protocol_implemented_training_not_authorized"
    assert config["training_authorized"] is False
    assert config["seeds"] == list(range(100, 801, 100))


def test_formal_v09_strict_config_is_single_seed_and_not_authorized():
    config = _read_json("formal_v09_strict_nesting.json")

    assert config["experiment_id"] == "R09-NEST"
    assert config["reference_variant"] == "classic_lstm_256_clean"
    assert config["candidate_variant"] == "nested_history_disabled"
    assert config["seeds"] == [100]
    assert config["training_authorized"] is False
    assert config["protocol_sha256"] == _sha256(CONFIG_ROOT / "formal_v09_protocol.json")


def test_formal_v09_registry_rows_are_unique_and_unrun():
    with (IDEA_ROOT / "registry.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))

    for experiment_id in ("P09-FORMAL", "R09-NEST", "B09-CLASSIC", "B09-CAPACITY", "E09-CONTINUOUS"):
        selected = [row for row in rows if row["exp_id"] == experiment_id]
        assert len(selected) == 1
        assert selected[0]["status"] == "protocol_implemented_training_not_authorized"
        assert selected[0]["best_checkpoint"] == ""
        assert selected[0]["metrics_path"] == ""

    assert not (REPO_ROOT / "results/26_historical_band_experts/formal_v09").exists()
