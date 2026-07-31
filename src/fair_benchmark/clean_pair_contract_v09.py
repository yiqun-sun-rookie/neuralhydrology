"""Frozen scoring-governance contract for the formal version-09 clean comparison."""
from __future__ import annotations

from collections.abc import Mapping
import hashlib
import json
from pathlib import Path


class CleanPairContractError(ValueError):
    """Raised when the clean-pair contract or its parent protocol drifts."""


CLEAN_PAIR_FORBIDDEN_PATTERNS_V09 = [
    r"usgs_streamflow",
    r"streamflow_qc",
    r"camels_hydro",
    r"QObs",
    r"_obs_eval\.parquet",
    r"runoff_ratio",
    r"baseflow_index",
    r"\bq_mean\b",
    r"\bq5\b",
    r"\bq95\b",
    r"high_q_freq",
    r"low_q_freq",
    r"zero_q_freq",
    r"hfd_mean",
    r"slope_fdc",
    r"track0_forcing_only_baseline_per_basin_nse",
    r"track0_forcing_only_secret_holdout_basins",
    r"portfolio_ledger",
    r"fair_benchmark[/\\]experiments[/\\].*report\.json",
]
LEGACY_FROZEN_MANIFEST_SHA256_V09 = (
    "461eb70e53ed4067eb454a0d72cc198f05ab9797c24d093bf927be849288b44c"
)
LEGACY_TRACK_SPEC_SHA256_V09 = (
    "8fb707cb5e2ec0f8edbf3f191f9ce836d259e8a31286466da63e6e62791388fb"
)


_CONTRACT_ID = "S09C-CLEAN-PAIR"
_TRACK_ID = "track0_forcing_only_clean_v09"
_PROTOCOL_ID = "P09-FORMAL"
_PROTOCOL_SHA256 = "b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8"
_PROTOCOL_CANONICAL_SHA256 = "09f39bb947c9895825774fdab43616b07eb3ac4e2ba79a010a12be5496a38fb8"
_CONTRACT_CANONICAL_SHA256 = "77bca4c384f4bd0ebb9438ca49c7f6186ff7e1cb8217ad9fc9c2dccaf5ad2779"
_PERMITTED_SUPERSESSIONS = (
    "/sealed_scoring_id",
    "/track",
    "/legacy_reference/description",
    "/legacy_frozen_manifest_issue/must_be_resolved_before_scoring_authorization",
    "/success_gates/secret_holdout_median_delta_at_least",
    "/success_gates/secret_retained_public_fraction_at_least",
)
_EXPECTED_TOP_LEVEL_KEYS = {
    "contract_id",
    "track_id",
    "protocol_id",
    "protocol_sha256",
    "protocol_scoring_supersession",
    "roles",
    "selection_provenance",
    "ensemble_paths",
    "prediction_contract",
    "trusted_frozen_inputs",
    "postseal_holdout",
    "legacy_nonqualifying_inputs",
    "primary_gate",
    "capacity_comparison",
    "historical_reference",
    "execution",
}
_EXPECTED_PROTOCOL_AUTHORIZATION = {
    "protocol_implementation": True,
    "synthetic_tests": True,
    "formal_target_bundle_generation": False,
    "training": False,
    "formal_prediction_generation": False,
    "official_scoring": False,
}


def _canonical_sha256(value: Mapping) -> str:
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _pointer_value(document: Mapping, pointer: str):
    value = document
    for raw_part in pointer.lstrip("/").split("/"):
        part = raw_part.replace("~1", "/").replace("~0", "~")
        if not isinstance(value, Mapping) or part not in value:
            raise CleanPairContractError(f"protocol value missing for {pointer}")
        value = value[part]
    return value


def _validate_protocol_boundary(protocol: Mapping, protocol_sha256: str) -> None:
    if protocol_sha256 != _PROTOCOL_SHA256:
        raise CleanPairContractError(
            f"protocol SHA-256 drift: expected {_PROTOCOL_SHA256}, got {protocol_sha256}"
        )
    if protocol.get("protocol_id") != _PROTOCOL_ID:
        raise CleanPairContractError("protocol value drift at /protocol_id")
    if _canonical_sha256(protocol) != _PROTOCOL_CANONICAL_SHA256:
        raise CleanPairContractError("protocol value drift outside the six permitted scoring semantics")
    if protocol.get("authorization") != _EXPECTED_PROTOCOL_AUTHORIZATION:
        raise CleanPairContractError("protocol value drift at /authorization")
    if protocol.get("formal_evaluation_target_access") is not False:
        raise CleanPairContractError("protocol value drift at /formal_evaluation_target_access")


def _validate_supersession(contract: Mapping, protocol: Mapping) -> None:
    supersession = contract.get("protocol_scoring_supersession")
    if not isinstance(supersession, Mapping):
        raise CleanPairContractError("protocol_scoring_supersession must be an object")
    permitted = supersession.get("permitted_semantic_supersessions")
    if permitted != list(_PERMITTED_SUPERSESSIONS):
        raise CleanPairContractError("permitted semantic supersessions drift")
    mapping = supersession.get("mapping")
    if not isinstance(mapping, Mapping) or set(mapping) != set(_PERMITTED_SUPERSESSIONS):
        raise CleanPairContractError("supersession mapping keys drift")
    for pointer in _PERMITTED_SUPERSESSIONS:
        entry = mapping[pointer]
        if not isinstance(entry, Mapping) or entry.get("protocol_value") != _pointer_value(protocol, pointer):
            raise CleanPairContractError(f"protocol value drift at {pointer}")
    if supersession.get("scientific_fields_overridden") != []:
        raise CleanPairContractError("scientific fields must not be overridden")
    if supersession.get("protocol_authorization_overridden") is not False:
        raise CleanPairContractError("protocol authorization must not be overridden")
    if supersession.get("formal_evaluation_target_access_overridden") is not False:
        raise CleanPairContractError("formal evaluation target access must not be overridden")
    if supersession.get("external_authorization_required") is not True:
        raise CleanPairContractError("external authorization must remain required")
    if supersession.get("legacy_route_authorizable") is not False:
        raise CleanPairContractError("the legacy route must remain non-authorizable")


def validate_clean_pair_contract_v09(
    contract: Mapping,
    *,
    protocol: Mapping,
    protocol_sha256: str,
) -> dict:
    """Validate the exact clean-route contract and its six protocol supersessions."""
    if not isinstance(contract, Mapping):
        raise CleanPairContractError("contract must be an object")
    if set(contract) != _EXPECTED_TOP_LEVEL_KEYS:
        raise CleanPairContractError("contract top-level keys drift")
    _validate_protocol_boundary(protocol, protocol_sha256)
    if contract.get("contract_id") != _CONTRACT_ID:
        raise CleanPairContractError("contract_id drift")
    if contract.get("track_id") != _TRACK_ID:
        raise CleanPairContractError("track_id drift")
    if contract.get("protocol_id") != _PROTOCOL_ID:
        raise CleanPairContractError("protocol_id drift")
    if contract.get("protocol_sha256") != _PROTOCOL_SHA256:
        raise CleanPairContractError("contract protocol SHA-256 drift")
    _validate_supersession(contract, protocol)
    if _canonical_sha256(contract) != _CONTRACT_CANONICAL_SHA256:
        raise CleanPairContractError("contract scientific or governance fields drift")
    return json.loads(json.dumps(contract))


def load_clean_pair_contract_v09(
    path: str | Path,
    *,
    protocol_path: str | Path,
) -> dict:
    """Load the contract and validate it against the exact protocol bytes."""
    path = Path(path)
    protocol_path = Path(protocol_path)
    try:
        contract = json.loads(path.read_text(encoding="utf-8"))
        protocol_bytes = protocol_path.read_bytes()
        protocol = json.loads(protocol_bytes.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CleanPairContractError(f"unable to load clean-pair contract: {exc}") from exc
    protocol_sha256 = hashlib.sha256(protocol_bytes).hexdigest()
    return validate_clean_pair_contract_v09(
        contract,
        protocol=protocol,
        protocol_sha256=protocol_sha256,
    )
