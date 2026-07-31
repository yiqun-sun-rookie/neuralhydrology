"""Observation-blind preflight for the formal version-09 clean paired score."""
from __future__ import annotations

import argparse
from collections.abc import Mapping
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

import psutil


IDEA_ROOT = Path(__file__).resolve().parent
REPO_ROOT = IDEA_ROOT.parents[1]
WORKTREE_SRC = (REPO_ROOT / "src").resolve()
if str(WORKTREE_SRC) not in sys.path:
    sys.path.insert(0, str(WORKTREE_SRC))

from clean_pair_bundle_v09 import build_clean_pair_bundle_v09  # noqa: E402
from fair_benchmark.clean_pair_authorization_v09 import (  # noqa: E402
    render_clean_pair_score_approval_text,
)
from fair_benchmark.clean_pair_contract_v09 import load_clean_pair_contract_v09  # noqa: E402
from fair_benchmark.governance import verify_chain  # noqa: E402
from fair_benchmark.leakage import scan_for_forbidden_access  # noqa: E402
from fair_benchmark.ledger import GENESIS, read_rows  # noqa: E402
from fair_benchmark.score_clean_pair_v09 import CLEAN_PAIR_FORBIDDEN_PATTERNS  # noqa: E402


_EXPERIMENT_ID = "S09C-CLEAN-PAIR"
_GIB = 2**30
_SELECTION_KEYS = ("candidate_config", "analysis_manifest", "summary", "independent_audit")
_TRUSTED_MODULES = (
    "fair_benchmark.score_clean_pair_v09",
    "fair_benchmark.clean_pair_authorization_v09",
    "fair_benchmark.clean_pair_contract_v09",
    "fair_benchmark.postseal_holdout_v09",
    "fair_benchmark.score",
    "fair_benchmark.gate",
    "fair_benchmark.stats",
    "fair_benchmark.metrics",
    "fair_benchmark.ledger",
    "fair_benchmark.io",
    "fair_benchmark.leakage",
    "fair_benchmark.tracks",
)


def _canonical_bytes(value: Mapping) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def _canonical_sha256(value: Mapping) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_json(path: Path) -> dict:
    def reject_constant(value: str):
        raise ValueError(f"non-finite JSON constant is forbidden: {value}")

    value = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def hash_tree_v09(root: str | Path) -> dict:
    """Hash every regular file by relative path and then hash the canonical map."""
    root = Path(root).resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"source bundle is missing: {root}")
    files = {
        path.relative_to(root).as_posix(): _sha256(path)
        for path in sorted(root.rglob("*"), key=lambda item: item.as_posix())
        if path.is_file()
    }
    if not files:
        raise ValueError("source bundle must contain at least one file")
    return {
        "root": str(root),
        "file_count": len(files),
        "files": files,
        "tree_sha256": hashlib.sha256(_canonical_bytes(files)).hexdigest(),
    }


def _ledger_snapshot(path: Path) -> dict:
    rows = read_rows(path)
    chain = verify_chain(path)
    return {
        "row_count": len(rows),
        "sha256": _sha256(path) if path.is_file() else hashlib.sha256(b"").hexdigest(),
        "last_row_hash": rows[-1].get("row_hash", "") if rows else GENESIS,
        "experiment_id_count": sum(row.get("experiment_id") == _EXPERIMENT_ID for row in rows),
        "chain_breaks": len(chain["breaks"]),
    }


def _module_import_probe() -> dict:
    script = (
        "import importlib,json;"
        f"names={list(_TRUSTED_MODULES)!r};"
        "print(json.dumps({n:str(importlib.import_module(n).__file__) for n in names},sort_keys=True))"
    )
    environment = dict(os.environ)
    environment["PYTHONPATH"] = str(WORKTREE_SRC)
    completed = subprocess.run(
        [sys.executable, "-I", "-c", "import sys;sys.path.insert(0," + repr(str(WORKTREE_SRC)) + ");" + script],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
        timeout=60,
    )
    paths = json.loads(completed.stdout.strip())
    trusted_root = (WORKTREE_SRC / "fair_benchmark").resolve()
    for name, raw_path in paths.items():
        if not Path(raw_path).resolve().is_relative_to(trusted_root):
            raise RuntimeError(f"trusted module imported outside this worktree: {name}")
    return {
        "python_executable": str(Path(sys.executable).resolve()),
        "worktree_src": str(WORKTREE_SRC),
        "pythonpath": str(WORKTREE_SRC),
        "module_paths": paths,
    }


def _verify_artifacts(
    contract: Mapping,
    bundle: Mapping,
    seal: Mapping,
) -> tuple[int, int, int]:
    upstream = seal.get("upstream_artifacts")
    evidence = bundle.get("upstream_evidence")
    if not isinstance(upstream, Mapping) or not isinstance(evidence, Mapping):
        raise ValueError("upstream artifact declarations are missing")
    if set(upstream) != set(evidence):
        raise ValueError("upstream artifact key set drift")
    for key, record in upstream.items():
        if not isinstance(record, Mapping):
            raise ValueError(f"upstream artifact declaration is invalid: {key}")
        path = Path(str(record.get("path", "")))
        digest = _sha256(path)
        if digest != record.get("sha256") or digest != evidence[key]:
            raise ValueError(f"upstream artifact SHA-256 drift: {key}")
        payload = _load_json(path)
        if payload.get("status") != record.get("required_status"):
            raise ValueError(f"upstream artifact status drift: {key}")

    selections = seal.get("selection_artifacts")
    provenance = contract.get("selection_provenance")
    if not isinstance(selections, Mapping) or set(selections) != set(_SELECTION_KEYS):
        raise ValueError("selection artifact declarations are incomplete")
    if not isinstance(provenance, Mapping):
        raise ValueError("selection provenance is missing")
    if (
        provenance.get("status") != "complete_multiseed_go"
        or provenance.get("formal_observations_used") is not False
        or provenance.get("may_reselect") is not False
    ):
        raise ValueError("selection provenance status or sealed-selection boundary drift")
    for key in _SELECTION_KEYS:
        record = selections[key]
        if not isinstance(record, Mapping):
            raise ValueError(f"selection artifact declaration is invalid: {key}")
        digest = _sha256(Path(str(record.get("path", ""))))
        if digest != record.get("sha256") or digest != provenance.get(f"{key}_sha256"):
            raise ValueError(f"selection artifact SHA-256 drift: {key}")

    checkpoints = seal.get("final_checkpoints")
    if not isinstance(checkpoints, list) or len(checkpoints) != 24:
        raise ValueError("exactly 24 final checkpoint declarations are required")
    for index, record in enumerate(checkpoints):
        if not isinstance(record, Mapping):
            raise ValueError(f"checkpoint declaration is invalid: {index}")
        if _sha256(Path(str(record.get("path", "")))) != record.get("sha256"):
            raise ValueError(f"checkpoint SHA-256 drift: {index}")
    return len(upstream), len(selections), len(checkpoints)


def _verify_trusted_inputs(contract: Mapping, trusted_root: Path) -> dict:
    trusted = contract.get("trusted_frozen_inputs")
    legacy = contract.get("legacy_nonqualifying_inputs")
    if not isinstance(trusted, Mapping) or not isinstance(legacy, Mapping):
        raise ValueError("trusted or legacy frozen input declarations are missing")
    verified = {}
    for key in ("answer_key", "basins"):
        record = trusted[key]
        path = (trusted_root / str(record["relative_path"])).resolve()
        if not path.is_relative_to(trusted_root.resolve()) or _sha256(path) != record.get("sha256"):
            raise ValueError(f"trusted frozen input SHA-256 drift: {key}")
        verified[key] = {
            "path": str(path),
            "sha256": record["sha256"],
            "content_parsed": key != "answer_key",
        }
    for key, required_status in (
        ("secret_holdout", "legacy_reused_holdout_nonqualifying"),
        ("historical_baseline", "historical_reference_nonqualifying"),
    ):
        record = legacy[key]
        path = (trusted_root / str(record["relative_path"])).resolve()
        if (
            not path.is_relative_to(trusted_root.resolve())
            or _sha256(path) != record.get("sha256")
            or record.get("status") != required_status
            or record.get("qualifying") is not False
        ):
            raise ValueError(f"legacy nonqualifying input drift: {key}")
    return verified


def _require_clean_worktree() -> dict:
    completed = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if completed.stdout.strip():
        raise ValueError("worktree is not clean")
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout.strip()
    return {"clean": True, "head": head}


def audit_clean_pair_score_preflight_v09(
    contract_path: str | Path,
    bundle_path: str | Path,
    prediction_seal_path: str | Path,
    source_bundle: str | Path,
    ledger_path: str | Path,
    trusted_frozen_root: str | Path,
    *,
    available_memory_bytes: int | None = None,
    require_clean_worktree: bool = True,
) -> dict:
    """Recompute every non-observational score binding and return a fail-closed report."""
    errors: list[str] = []
    report: dict = {
        "status": "not_ready_for_clean_pair_score_authorization",
        "answer_content_parsed": False,
        "official_score_called": False,
        "errors": errors,
    }
    try:
        contract_path = Path(contract_path)
        bundle_path = Path(bundle_path)
        seal_path = Path(prediction_seal_path)
        source_bundle = Path(source_bundle)
        ledger_path = Path(ledger_path)
        trusted_root = Path(trusted_frozen_root).resolve()
        protocol_path = IDEA_ROOT / "configs" / "formal_v09_protocol.json"
        contract = load_clean_pair_contract_v09(contract_path, protocol_path=protocol_path)
        bundle = _load_json(bundle_path)
        seal = _load_json(seal_path)

        if _canonical_sha256(seal) != bundle.get("prediction_seal_sha256"):
            raise ValueError("prediction seal canonical SHA-256 drift")
        formal_root = bundle_path.resolve().parents[1]
        rebuilt = build_clean_pair_bundle_v09(contract, seal, formal_root)
        if rebuilt != bundle:
            raise ValueError("saved clean-pair bundle differs from a complete rebuild")

        source_tree = hash_tree_v09(source_bundle)
        if source_tree["tree_sha256"] != bundle.get("source_bundle", {}).get("tree_sha256"):
            raise ValueError("candidate source bundle tree SHA-256 drift")
        hits = scan_for_forbidden_access(source_bundle, CLEAN_PAIR_FORBIDDEN_PATTERNS)
        if hits:
            raise ValueError(f"candidate source bundle has {len(hits)} forbidden-access scan hits")

        upstream_count, selection_count, checkpoint_count = _verify_artifacts(contract, bundle, seal)
        trusted_inputs = _verify_trusted_inputs(contract, trusted_root)
        ledger = _ledger_snapshot(ledger_path)
        if ledger["chain_breaks"] or ledger["experiment_id_count"]:
            raise ValueError("ledger chain is broken or the clean-pair experiment already exists")

        total_memory = int(psutil.virtual_memory().total)
        available = (
            int(psutil.virtual_memory().available)
            if available_memory_bytes is None
            else int(available_memory_bytes)
        )
        required = max(12 * _GIB, math.ceil(0.40 * total_memory))
        if available < required:
            raise ValueError(f"available physical memory below scoring preflight threshold: {available} < {required}")

        output_root = formal_root
        forbidden_outputs = (
            output_root / "authorizations" / "clean_pair_scoring_authorization.json",
            output_root / "clean_pair_scoring_authorization_consumed.json",
            output_root / "clean_pair_holdout_draw_receipt.json",
            output_root / "clean_pair_score_attempt_01" / "report.json",
        )
        existing = [str(path) for path in forbidden_outputs if path.exists()]
        if existing:
            raise ValueError(f"score-attempt output already exists: {existing}")

        worktree = _require_clean_worktree() if require_clean_worktree else {"clean_check_skipped": True}
        runtime = _module_import_probe()
        report.update({
            "status": "ready_for_clean_pair_score_authorization",
            "contract_sha256": bundle["contract_sha256"],
            "bundle_sha256": bundle["bundle_sha256"],
            "prediction_seal_sha256": bundle["prediction_seal_sha256"],
            "prediction_files_verified": len(bundle["predictions"]),
            "checkpoint_files_verified": checkpoint_count,
            "upstream_artifacts_verified": upstream_count,
            "selection_artifacts_verified": selection_count,
            "candidate_source_scan_hits": 0,
            "source_tree": source_tree,
            "trusted_inputs": trusted_inputs,
            "ledger": ledger,
            "runtime": runtime,
            "worktree": worktree,
            "memory": {
                "total_bytes": total_memory,
                "available_bytes": available,
                "required_available_bytes": required,
            },
            "score_approval_text": render_clean_pair_score_approval_text(bundle["bundle_sha256"]),
        })
    except Exception as exc:  # fail closed and preserve all diagnostics in one report
        errors.append(f"{type(exc).__name__}: {exc}")
    return report


def _exclusive_write(path: Path, payload: Mapping) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, indent=2, ensure_ascii=False, allow_nan=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", required=True)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--prediction-seal", required=True)
    parser.add_argument("--source-bundle", required=True)
    parser.add_argument("--trusted-frozen-root", required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args(argv)
    report = audit_clean_pair_score_preflight_v09(
        args.contract,
        args.bundle,
        args.prediction_seal,
        args.source_bundle,
        args.ledger,
        args.trusted_frozen_root,
    )
    _exclusive_write(Path(args.report), report)
    print(json.dumps(report, sort_keys=True, ensure_ascii=False, allow_nan=False))
    return 0 if report["status"] == "ready_for_clean_pair_score_authorization" else 1


if __name__ == "__main__":
    raise SystemExit(main())
