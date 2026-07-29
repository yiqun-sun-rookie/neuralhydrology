"""Read-only identity verification for the frozen eight-seed classic reference."""
from __future__ import annotations

from collections.abc import Mapping
import hashlib
from pathlib import Path


class LegacyReferenceVerificationError(RuntimeError):
    """Raised when a frozen classic reference file or metadata field drifts."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _yaml_scalar(config_text: str, key: str) -> str:
    prefix = f"{key}:"
    matches = []
    for line in config_text.splitlines():
        stripped = line.strip()
        if stripped.startswith(prefix):
            value = stripped[len(prefix):].split("#", 1)[0].strip().strip("'\"")
            matches.append(value)
    if len(matches) != 1 or not matches[0]:
        raise LegacyReferenceVerificationError(
            f"expected exactly one nonempty {key!r} field in run config"
        )
    return matches[0]


def _require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise LegacyReferenceVerificationError(f"missing {label}: {path}")


def verify_legacy_reference_v09(
    protocol: Mapping,
    results_root: str | Path,
) -> dict:
    """Verify only the registered configs and epoch-30 checkpoints under a result root."""
    legacy = protocol.get("legacy_reference")
    if not isinstance(legacy, Mapping):
        raise LegacyReferenceVerificationError("protocol has no legacy_reference mapping")
    commit_prefix = legacy.get("recorded_code_commit_prefix")
    runs = legacy.get("runs")
    if not isinstance(commit_prefix, str) or not commit_prefix:
        raise LegacyReferenceVerificationError("legacy reference commit prefix is missing")
    if not isinstance(runs, list) or not runs:
        raise LegacyReferenceVerificationError("legacy reference run list is missing")

    results_root = Path(results_root)
    if not results_root.is_dir():
        raise LegacyReferenceVerificationError(f"legacy result root is missing: {results_root}")

    verified_seeds: list[int] = []
    verified_run_ids: set[str] = set()
    for run in runs:
        if not isinstance(run, Mapping):
            raise LegacyReferenceVerificationError("legacy run entry must be a mapping")
        run_id = run.get("run_id")
        seed = run.get("seed")
        if not isinstance(run_id, str) or Path(run_id).name != run_id:
            raise LegacyReferenceVerificationError(f"invalid legacy run_id: {run_id!r}")
        if run_id in verified_run_ids:
            raise LegacyReferenceVerificationError(f"duplicate legacy run_id: {run_id}")
        if not isinstance(seed, int) or isinstance(seed, bool):
            raise LegacyReferenceVerificationError(f"invalid seed for {run_id}: {seed!r}")

        run_dir = results_root / run_id
        config_path = run_dir / "config.yml"
        checkpoint_path = run_dir / "model_epoch030.pt"
        _require_file(config_path, "run config")
        _require_file(checkpoint_path, "epoch-30 checkpoint")

        actual_config_hash = _sha256(config_path)
        if actual_config_hash != run.get("config_sha256"):
            raise LegacyReferenceVerificationError(
                f"{run_id} config SHA-256 drift: {actual_config_hash}"
            )
        actual_checkpoint_hash = _sha256(checkpoint_path)
        if actual_checkpoint_hash != run.get("checkpoint_epoch030_sha256"):
            raise LegacyReferenceVerificationError(
                f"{run_id} checkpoint SHA-256 drift: {actual_checkpoint_hash}"
            )

        config_text = config_path.read_text(encoding="utf-8")
        recorded_seed = _yaml_scalar(config_text, "seed")
        if recorded_seed != str(seed):
            raise LegacyReferenceVerificationError(
                f"{run_id} seed drift: {recorded_seed!r} != {seed}"
            )
        recorded_commit = _yaml_scalar(config_text, "commit_hash")
        if recorded_commit != commit_prefix:
            raise LegacyReferenceVerificationError(
                f"{run_id} commit prefix drift: {recorded_commit!r} != {commit_prefix!r}"
            )

        verified_run_ids.add(run_id)
        verified_seeds.append(seed)

    return {
        "verified": True,
        "run_count": len(runs),
        "file_count": 2 * len(runs),
        "seeds": verified_seeds,
        "recorded_code_commit_prefix": commit_prefix,
    }
