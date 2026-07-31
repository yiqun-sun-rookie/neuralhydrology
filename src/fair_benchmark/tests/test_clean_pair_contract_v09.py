import copy
import hashlib
import json
from pathlib import Path

import pytest

from fair_benchmark.clean_pair_contract_v09 import (
    CLEAN_PAIR_FORBIDDEN_PATTERNS_V09,
    CleanPairContractError,
    load_clean_pair_contract_v09,
    validate_clean_pair_contract_v09,
)
from fair_benchmark.leakage import DEFAULT_FORBIDDEN


_REPO_ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = (
    _REPO_ROOT
    / "src"
    / "26_historical_band_experts"
    / "configs"
    / "formal_v09_clean_pair_scoring_contract.json"
)
PROTOCOL_PATH = (
    _REPO_ROOT
    / "src"
    / "26_historical_band_experts"
    / "configs"
    / "formal_v09_protocol.json"
)
PROTOCOL = json.loads(PROTOCOL_PATH.read_text(encoding="utf-8"))
PROTOCOL_SHA256 = hashlib.sha256(PROTOCOL_PATH.read_bytes()).hexdigest()


def test_clean_pair_contract_freezes_roles_gates_and_one_call():
    validated = load_clean_pair_contract_v09(
        CONTRACT_PATH,
        protocol_path=PROTOCOL_PATH,
    )
    assert validated["contract_id"] == "S09C-CLEAN-PAIR"
    assert validated["track_id"] == "track0_forcing_only_clean_v09"
    supersession = validated["protocol_scoring_supersession"]
    assert len(supersession["permitted_semantic_supersessions"]) == 6
    assert supersession["scientific_fields_overridden"] == []
    assert supersession["protocol_authorization_overridden"] is False
    assert supersession["external_authorization_required"] is True
    assert supersession["legacy_route_authorizable"] is False
    assert validated["roles"] == {
        "baseline": "B09-CLASSIC",
        "capacity_control": "B09-CAPACITY",
        "challenger": "E09-CONTINUOUS",
    }
    assert validated["execution"] == {
        "score_submission_calls": 1,
        "ledger_appends": 1,
        "retries": 0,
        "allow_unconfirmed": False,
    }
    assert validated["historical_reference"]["qualifying"] is False
    assert validated["selection_provenance"]["status"] == "complete_multiseed_go"
    assert validated["selection_provenance"]["may_reselect"] is False
    assert validated["postseal_holdout"]["method"] == "postseal_nonce_sha256_rank_v1"
    assert validated["postseal_holdout"]["holdout_count"] == 107
    assert validated["postseal_holdout"]["public_count"] == 424
    assert validated["legacy_nonqualifying_inputs"]["secret_holdout"]["qualifying"] is False


def test_clean_pair_contract_freezes_complete_forbidden_pattern_order():
    assert CLEAN_PAIR_FORBIDDEN_PATTERNS_V09 == list(DEFAULT_FORBIDDEN) + [
        r"track0_forcing_only_baseline_per_basin_nse",
        r"track0_forcing_only_secret_holdout_basins",
        r"portfolio_ledger",
        r"fair_benchmark[/\\]experiments[/\\].*report\.json",
    ]


@pytest.mark.parametrize(
    ("path", "value"),
    [
        (("primary_gate", "min_effect"), 0.009),
        (("execution", "score_submission_calls"), 2),
        (("roles", "baseline"), "legacy_lstm_ensemble"),
        (("historical_reference", "qualifying"), True),
        (("postseal_holdout", "holdout_count"), 106),
        (("legacy_nonqualifying_inputs", "secret_holdout"), {}),
        (
            ("protocol_scoring_supersession", "scientific_fields_overridden"),
            ["/forcing_product"],
        ),
        (
            ("protocol_scoring_supersession", "permitted_semantic_supersessions"),
            ["/track"],
        ),
    ],
)
def test_clean_pair_contract_rejects_scientific_drift(path, value):
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    changed = copy.deepcopy(contract)
    changed[path[0]][path[1]] = value
    with pytest.raises(CleanPairContractError):
        validate_clean_pair_contract_v09(
            changed,
            protocol=PROTOCOL,
            protocol_sha256=PROTOCOL_SHA256,
        )


def test_clean_pair_contract_rejects_unknown_keys():
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    contract["unexpected"] = True
    with pytest.raises(CleanPairContractError, match="contract"):
        validate_clean_pair_contract_v09(
            contract,
            protocol=PROTOCOL,
            protocol_sha256=PROTOCOL_SHA256,
        )


def test_clean_pair_contract_rejects_protocol_byte_or_value_drift():
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    with pytest.raises(CleanPairContractError, match="protocol SHA-256"):
        validate_clean_pair_contract_v09(
            contract,
            protocol=PROTOCOL,
            protocol_sha256="f" * 64,
        )
    changed_protocol = copy.deepcopy(PROTOCOL)
    changed_protocol["success_gates"]["public_median_paired_delta_at_least"] = 0.009
    with pytest.raises(CleanPairContractError, match="protocol value"):
        validate_clean_pair_contract_v09(
            contract,
            protocol=changed_protocol,
            protocol_sha256=PROTOCOL_SHA256,
        )
