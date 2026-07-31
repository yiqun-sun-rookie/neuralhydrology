"""Deterministically derive the post-seal version-09 holdout from one nonce."""
from __future__ import annotations

from collections.abc import Mapping, Sequence
import hashlib
import re


class PostsealHoldoutError(ValueError):
    """Raised when a post-seal holdout input violates the frozen contract."""


_DOMAIN_SEPARATOR = "P09C-CLEAN-HOLDOUT-V1"
_ROLES = ("baseline", "capacity_control", "challenger")
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_BASIN_COUNT = 531
_HOLDOUT_COUNT = 107
_PUBLIC_COUNT = 424


def _require_hex64(value: object, name: str) -> str:
    if not isinstance(value, str) or _HEX64.fullmatch(value) is None:
        raise PostsealHoldoutError(f"{name} must be 64 lowercase hexadecimal characters")
    return value


def derive_postseal_holdout_v09(
    basins: Sequence[str],
    *,
    protocol_sha256: str,
    prediction_sha256: Mapping[str, str],
    nonce_hex: str,
    holdout_count: int,
) -> dict:
    """Return the exact 107/424 split bound to three sealed prediction files."""
    basin_ids = [str(basin) for basin in basins]
    if len(basin_ids) != _BASIN_COUNT or len(set(basin_ids)) != _BASIN_COUNT:
        raise PostsealHoldoutError("basins must contain exactly 531 unique identifiers")
    if any(not basin for basin in basin_ids):
        raise PostsealHoldoutError("basin identifiers must be non-empty")
    if int(holdout_count) != _HOLDOUT_COUNT:
        raise PostsealHoldoutError("holdout_count must be 107")
    protocol_sha256 = _require_hex64(protocol_sha256, "protocol_sha256")
    if not isinstance(prediction_sha256, Mapping) or tuple(prediction_sha256) != _ROLES:
        raise PostsealHoldoutError("prediction_sha256 roles or order drift")
    prediction_hashes = {
        role: _require_hex64(prediction_sha256[role], f"prediction_sha256[{role}]")
        for role in _ROLES
    }
    nonce_hex = _require_hex64(nonce_hex, "nonce_hex")

    fields = [
        _DOMAIN_SEPARATOR,
        protocol_sha256,
        prediction_hashes["baseline"],
        prediction_hashes["capacity_control"],
        prediction_hashes["challenger"],
        nonce_hex,
    ]
    partition_salt_sha256 = hashlib.sha256("\n".join(fields).encode("utf-8")).hexdigest()
    ranked = sorted(
        (
            hashlib.sha256(f"{partition_salt_sha256}\n{basin}".encode("utf-8")).hexdigest(),
            basin,
        )
        for basin in basin_ids
    )
    holdout_ids = {basin for _, basin in ranked[:_HOLDOUT_COUNT]}
    if len(holdout_ids) != _HOLDOUT_COUNT or len(set(basin_ids) - holdout_ids) != _PUBLIC_COUNT:
        raise PostsealHoldoutError("derived holdout counts drift")
    holdout_set_sha256 = hashlib.sha256(
        "".join(f"{basin}\n" for basin in sorted(holdout_ids)).encode("utf-8")
    ).hexdigest()
    return {
        "method": "postseal_nonce_sha256_rank_v1",
        "holdout_count": _HOLDOUT_COUNT,
        "public_count": _PUBLIC_COUNT,
        "holdout_ids": holdout_ids,
        "nonce_hex": nonce_hex,
        "nonce_sha256": hashlib.sha256(bytes.fromhex(nonce_hex)).hexdigest(),
        "partition_salt_sha256": partition_salt_sha256,
        "holdout_set_sha256": holdout_set_sha256,
    }


def public_partition_summary(partition: Mapping) -> dict:
    """Return the persistable split summary without nonce material or basin identities."""
    required = (
        "method",
        "holdout_count",
        "public_count",
        "nonce_sha256",
        "partition_salt_sha256",
        "holdout_set_sha256",
    )
    if any(key not in partition for key in required):
        raise PostsealHoldoutError("partition summary fields are incomplete")
    return {key: partition[key] for key in required}
