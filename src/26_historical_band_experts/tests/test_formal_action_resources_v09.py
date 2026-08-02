import hashlib
import json
from pathlib import Path
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG = IDEA_ROOT / "configs/formal_v09_protocol.json"
sys.path.insert(0, str(IDEA_ROOT))

GIB = 2**30
MIB = 2**20


def _config() -> dict:
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def _rehash(estimate: dict) -> None:
    estimate["evidence_sha256"] = hashlib.sha256(
        json.dumps(
            estimate["evidence"],
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")).hexdigest()


def test_target_bundle_estimate_matches_streaming_formula():
    from formal_action_resources_v09 import (
        build_formal_action_peak_estimate_v09,
        validate_formal_action_peak_estimate_v09,
    )

    config = _config()
    estimate = build_formal_action_peak_estimate_v09(
        config,
        "formal_target_bundle_generation",
    )
    resources = config["formal_action_resources"]["target_bundle"]
    expected = (resources["fixed_overhead_mib"] * MIB +
                resources["source_rows_per_basin"] * resources["source_row_bytes_upper_bound"] +
                resources["target_rows_per_basin"] * resources["target_row_bytes_upper_bound"] +
                resources["serialization_buffer_mib"] * MIB)

    assert estimate["method"] == "analytical_target_bundle_working_set_v1"
    assert estimate["estimated_peak_bytes"] == expected
    assert estimate["evidence"]["writer"] == "stream_one_basin_v1"
    assert validate_formal_action_peak_estimate_v09(
        config,
        "formal_target_bundle_generation",
        estimate,
    )["estimated_peak_bytes"] == expected


@pytest.mark.parametrize(
    ("variant", "parameter_count", "recent_hidden", "history_steps"),
    [
        ("strict_nesting_pair", 594_434, 512, 0),
        ("classic_lstm_256_clean", 297_217, 256, 0),
        ("classic_lstm_369_capacity", 595_198, 369, 0),
        ("continuous_multiscale_history", 596_737, 256, 120),
    ],
)
def test_training_estimate_binds_variant_geometry(
    variant,
    parameter_count,
    recent_hidden,
    history_steps,
):
    from formal_action_resources_v09 import (
        build_formal_action_peak_estimate_v09,
        validate_formal_action_peak_estimate_v09,
    )

    config = _config()
    estimate = build_formal_action_peak_estimate_v09(config, "training", variant=variant)
    evidence = estimate["evidence"]

    assert estimate["method"] == "analytical_training_working_set_v1"
    assert evidence["parameter_count"] == parameter_count
    assert evidence["recent_hidden_size"] == recent_hidden
    assert evidence["history_steps"] == history_steps
    assert evidence["batch_size"] == 256
    assert evidence["accelerator_estimated_peak_bytes"] > 0
    validate_formal_action_peak_estimate_v09(
        config,
        "training",
        estimate,
        variant=variant,
    )


def test_prediction_estimate_binds_full_prediction_geometry():
    from formal_action_resources_v09 import (
        build_formal_action_peak_estimate_v09,
        validate_formal_action_peak_estimate_v09,
    )

    config = _config()
    estimate = build_formal_action_peak_estimate_v09(
        config,
        "formal_prediction_generation",
        variant="continuous_multiscale_history",
    )

    assert estimate["method"] == "analytical_prediction_working_set_v1"
    assert estimate["evidence"]["prediction_rows"] == 1_939_212
    assert estimate["evidence"]["prediction_chunk_rows"] == 50_000
    assert estimate["evidence"]["accelerator_estimated_peak_bytes"] > 0
    validate_formal_action_peak_estimate_v09(
        config,
        "formal_prediction_generation",
        estimate,
        variant="continuous_multiscale_history",
    )


@pytest.mark.parametrize(
    ("action", "variant", "field", "replacement"),
    [
        ("formal_target_bundle_generation", None, "target_rows_per_basin", 1),
        ("training", "classic_lstm_369_capacity", "batch_size", 1),
        ("training", "classic_lstm_369_capacity", "parameter_count", 1),
        (
            "formal_prediction_generation",
            "continuous_multiscale_history",
            "forcing_rows",
            1,
        ),
        (
            "formal_prediction_generation",
            "continuous_multiscale_history",
            "protocol_canonical_sha256",
            "0" * 64,
        ),
    ],
)
def test_rehashed_smaller_or_drifted_action_evidence_is_rejected(
    action,
    variant,
    field,
    replacement,
):
    from formal_action_resources_v09 import (
        build_formal_action_peak_estimate_v09,
        validate_formal_action_peak_estimate_v09,
    )
    from memory_safety_v09 import MemorySafetyError

    config = _config()
    estimate = build_formal_action_peak_estimate_v09(config, action, variant=variant)
    estimate["evidence"][field] = replacement
    _rehash(estimate)

    with pytest.raises(MemorySafetyError):
        validate_formal_action_peak_estimate_v09(
            config,
            action,
            estimate,
            variant=variant,
        )


def test_action_estimator_rejects_missing_or_irrelevant_variant():
    from formal_action_resources_v09 import build_formal_action_peak_estimate_v09

    config = _config()
    with pytest.raises(ValueError, match="variant is required"):
        build_formal_action_peak_estimate_v09(config, "training")
    with pytest.raises(ValueError, match="variant is not accepted"):
        build_formal_action_peak_estimate_v09(
            config,
            "formal_target_bundle_generation",
            variant="classic_lstm_256_clean",
        )


def test_action_specific_validator_rejects_cross_action_evidence():
    from formal_action_resources_v09 import (
        build_formal_action_peak_estimate_v09,
        validate_formal_action_peak_estimate_v09,
    )
    from memory_safety_v09 import MemorySafetyError

    config = _config()
    training = build_formal_action_peak_estimate_v09(
        config,
        "training",
        variant="classic_lstm_256_clean",
    )

    with pytest.raises(MemorySafetyError):
        validate_formal_action_peak_estimate_v09(
            config,
            "formal_prediction_generation",
            training,
            variant="continuous_multiscale_history",
        )


def test_validator_rejects_smaller_model_evidence_for_larger_requested_variant():
    from formal_action_resources_v09 import (
        build_formal_action_peak_estimate_v09,
        validate_formal_action_peak_estimate_v09,
    )
    from memory_safety_v09 import MemorySafetyError

    config = _config()
    classic = build_formal_action_peak_estimate_v09(
        config,
        "training",
        variant="classic_lstm_256_clean",
    )

    with pytest.raises(MemorySafetyError, match="requested training variant"):
        validate_formal_action_peak_estimate_v09(
            config,
            "training",
            classic,
            variant="continuous_multiscale_history",
        )


def test_accelerator_gate_requires_peak_and_reserve_to_fit():
    from formal_action_resources_v09 import (
        AcceleratorMemorySnapshot,
        assert_accelerator_safe_v09,
        build_formal_action_peak_estimate_v09,
    )
    from memory_safety_v09 import MemorySafetyError

    config = _config()
    estimate = build_formal_action_peak_estimate_v09(
        config,
        "training",
        variant="classic_lstm_256_clean",
    )
    peak = estimate["evidence"]["accelerator_estimated_peak_bytes"]
    guarded = int(peak * 1.25 + 0.999999)
    passing = AcceleratorMemorySnapshot(
        device_index=0,
        device_name="synthetic-cuda",
        total_bytes=8 * GIB,
        available_bytes=guarded + 1 * GIB,
    )
    failing = AcceleratorMemorySnapshot(
        device_index=0,
        device_name="synthetic-cuda",
        total_bytes=8 * GIB,
        available_bytes=guarded + 1 * GIB - 1,
    )

    assert assert_accelerator_safe_v09(
        config,
        "training",
        estimate,
        passing,
        variant="classic_lstm_256_clean",
    )["safe"]
    with pytest.raises(MemorySafetyError, match="accelerator reserve"):
        assert_accelerator_safe_v09(
            config,
            "training",
            estimate,
            failing,
            variant="classic_lstm_256_clean",
        )


def test_target_bundle_does_not_require_accelerator_snapshot():
    from formal_action_resources_v09 import (
        assert_accelerator_safe_v09,
        build_formal_action_peak_estimate_v09,
    )

    config = _config()
    estimate = build_formal_action_peak_estimate_v09(
        config,
        "formal_target_bundle_generation",
    )

    assert assert_accelerator_safe_v09(
        config,
        "formal_target_bundle_generation",
        estimate,
        None,
    ) == {
        "required": False,
        "safe": True
    }
