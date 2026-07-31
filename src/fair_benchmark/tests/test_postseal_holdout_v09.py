from pathlib import Path

import pytest

from fair_benchmark.postseal_holdout_v09 import (
    PostsealHoldoutError,
    derive_postseal_holdout_v09,
    public_partition_summary,
)


_REPO_ROOT = Path(__file__).resolve().parents[3]
FROZEN_BASIN_LIST = (
    _REPO_ROOT / "src" / "fair_benchmark" / "frozen" / "track0_forcing_only_basins.txt"
)
PROTOCOL_SHA = "20a37c4dfafebc7e49aec812a6fc27079081def55e78b4942df626e0bbd8bff1"
PREDICTION_SHA = {
    "baseline": "a" * 64,
    "capacity_control": "b" * 64,
    "challenger": "c" * 64,
}
BASINS = [f"{index:08d}" for index in range(531)]


def test_postseal_holdout_is_deterministic_complete_and_prediction_bound():
    first = derive_postseal_holdout_v09(
        BASINS,
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=PREDICTION_SHA,
        nonce_hex="1" * 64,
        holdout_count=107,
    )
    second = derive_postseal_holdout_v09(
        list(reversed(BASINS)),
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=PREDICTION_SHA,
        nonce_hex="1" * 64,
        holdout_count=107,
    )
    assert first["holdout_ids"] == second["holdout_ids"]
    assert len(first["holdout_ids"]) == 107
    assert len(set(BASINS) - first["holdout_ids"]) == 424

    changed_prediction = derive_postseal_holdout_v09(
        BASINS,
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=dict(PREDICTION_SHA, challenger="f" * 64),
        nonce_hex="1" * 64,
        holdout_count=107,
    )
    changed_nonce = derive_postseal_holdout_v09(
        BASINS,
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=PREDICTION_SHA,
        nonce_hex="2" * 64,
        holdout_count=107,
    )
    assert first["holdout_set_sha256"] != changed_prediction["holdout_set_sha256"]
    assert first["holdout_set_sha256"] != changed_nonce["holdout_set_sha256"]
    assert "holdout_ids" not in public_partition_summary(first)
    assert "nonce_hex" not in public_partition_summary(first)


def test_postseal_holdout_matches_frozen_nonobservational_test_vector():
    basins = [
        line
        for line in FROZEN_BASIN_LIST.read_text(encoding="utf-8").splitlines()
        if line
    ]
    result = derive_postseal_holdout_v09(
        basins,
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=PREDICTION_SHA,
        nonce_hex="1" * 64,
        holdout_count=107,
    )
    assert result["partition_salt_sha256"] == (
        "5a8e4306a5ec61491d9ebfbfd6f05b88bd505ce08ee6d9b21b50cb3031ccb162"
    )
    assert result["holdout_set_sha256"] == (
        "869a48d9d81ed1a9a86cc2aa5d365e9532a8429a37efdc538ca17aa674366d45"
    )


@pytest.mark.parametrize(
    "kwargs",
    [
        {"basins": BASINS[:-1]},
        {"basins": BASINS[:-1] + [BASINS[0]]},
        {"protocol_sha256": "A" * 64},
        {"prediction_sha256": {"baseline": "a" * 64}},
        {"prediction_sha256": dict(PREDICTION_SHA, baseline="A" * 64)},
        {"nonce_hex": "1" * 63},
        {"holdout_count": 106},
    ],
)
def test_postseal_holdout_rejects_contract_drift(kwargs):
    inputs = {
        "basins": BASINS,
        "protocol_sha256": PROTOCOL_SHA,
        "prediction_sha256": PREDICTION_SHA,
        "nonce_hex": "1" * 64,
        "holdout_count": 107,
    }
    inputs.update(kwargs)
    with pytest.raises(PostsealHoldoutError):
        derive_postseal_holdout_v09(**inputs)
