"""Run one development-only automatic proposal and recommendation rehearsal.

This workflow exercises proposal registration, restricted execution, and development-only
recommendation. It does not generate arbitrary source code, open sealed evaluation data, run
the fair-benchmark scoring service, or make a baseline-outperformance claim.
"""

from __future__ import annotations

import hashlib
import json
import math
import statistics
from functools import partial
from pathlib import Path
from typing import Any

from unified_autoresearch.candidates.catalog import (
    PINNED_DEPENDENCIES,
    materialize_hbv_lite_candidate,
    materialize_reference_candidate,
)
from unified_autoresearch.runtime.resources import ResourceSnapshot
from unified_autoresearch.workflow.candidate_development import run_single_candidate_development
from unified_autoresearch.workflow.development_loop import (
    _artifact_manifest,
    _inside,
    _sha256_file,
    _validate_package,
    _write_json_exclusive,
)


POLICY_FIELDS = {
    "schema_version",
    "proposal_budget",
    "proposal_rule",
    "proposal_inputs",
    "result_dependent_proposal_inputs",
    "prediction_inputs",
    "training_supervision",
    "seed",
    "recommendation_rule",
    "candidate_pool",
}
PROPOSAL_FIELDS = {
    "candidate_key",
    "candidate_id",
    "category",
    "method_family",
    "priority",
    "seed",
    "hypothesis",
}
EXPECTED_PROPOSAL_INPUTS = [
    "approved_candidate_catalog",
    "declared_resource_budget",
    "prediction_information_contract",
]
APPROVED_CANDIDATES = {
    "hbv_lite": (
        "hbv-lite-calibrated-v1",
        "conceptual_rainfall_runoff",
        "hbv_lite",
    ),
    "deep_learning": (
        "reference-deep-learning-v1",
        "deep_learning",
        "multilayer_perceptron",
    ),
    "fusion": (
        "reference-fusion-v1",
        "fusion",
        "reservoir_regression_fusion",
    ),
    "custom_python": (
        "reference-custom-python-v1",
        "custom_python",
        "per_basin_mean",
    ),
}
SELECTION_PATH = Path(__file__).resolve().parents[1] / "selection" / "development_basins_v1.json"


def _policy_sha256(path: str | Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_and_validate_rehearsal_policy(path: str | Path) -> dict[str, Any]:
    """Validate the frozen, result-independent proposal policy and derive three proposals."""
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict) or set(value) != POLICY_FIELDS:
        raise ValueError("automatic rehearsal policy fields do not match the frozen schema")
    if (
        value["schema_version"] != "automatic_rehearsal_policy_v1"
        or value["proposal_budget"] != 3
        or value["proposal_rule"] != "lowest_priority_distinct_category_v1"
        or value["proposal_inputs"] != EXPECTED_PROPOSAL_INPUTS
        or value["result_dependent_proposal_inputs"] is not False
        or value["prediction_inputs"] != ["maurer_forcing", "static_attributes"]
        or value["training_supervision"] != "observed_discharge_development_only"
        or value["seed"] != 29
        or value["recommendation_rule"]
        != "descending_median_mean_nse_then_candidate_id_v1"
    ):
        raise ValueError("automatic rehearsal policy violates the frozen proposal boundary")
    pool = value["candidate_pool"]
    if not isinstance(pool, list) or len(pool) < value["proposal_budget"]:
        raise ValueError("candidate pool cannot satisfy the proposal budget")
    if any(not isinstance(item, dict) or set(item) != PROPOSAL_FIELDS for item in pool):
        raise ValueError("candidate pool entry fields do not match the frozen schema")
    if len({item["candidate_key"] for item in pool}) != len(pool):
        raise ValueError("candidate keys must be unique")
    if len({item["candidate_id"] for item in pool}) != len(pool):
        raise ValueError("candidate identifiers must be unique")
    if len({item["category"] for item in pool}) != len(pool):
        raise ValueError("candidate pool categories must be structurally distinct")
    if len({item["priority"] for item in pool}) != len(pool):
        raise ValueError("candidate priorities must be unique")
    for item in pool:
        approved = APPROVED_CANDIDATES.get(item["candidate_key"])
        if approved != (item["candidate_id"], item["category"], item["method_family"]):
            raise ValueError("candidate pool entry is not in the approved candidate catalog")
        if (
            not isinstance(item["priority"], int)
            or isinstance(item["priority"], bool)
            or item["priority"] < 1
            or item["seed"] != value["seed"]
            or not isinstance(item["hypothesis"], str)
            or not item["hypothesis"].strip()
        ):
            raise ValueError("candidate proposal declaration is invalid")
    proposals = sorted(pool, key=lambda item: (item["priority"], item["candidate_id"]))[
        : value["proposal_budget"]
    ]
    if len({item["category"] for item in proposals}) != value["proposal_budget"]:
        raise ValueError("proposal rule did not produce three structurally distinct candidates")
    result = dict(value)
    result["proposals"] = [dict(item) for item in proposals]
    return result


def freeze_rehearsal_proposals(policy_path: str | Path, output_path: str | Path) -> dict[str, Any]:
    """Validate first, then exclusively persist the result-independent proposal registry."""
    policy = load_and_validate_rehearsal_policy(policy_path)
    registry = {
        "schema_version": "automatic_rehearsal_proposal_registry_v1",
        "policy_sha256": _policy_sha256(policy_path),
        "proposal_rule": policy["proposal_rule"],
        "proposal_inputs": policy["proposal_inputs"],
        "result_dependent_proposal_inputs": False,
        "prediction_inputs": policy["prediction_inputs"],
        "training_supervision": policy["training_supervision"],
        "proposal_count": len(policy["proposals"]),
        "proposals": policy["proposals"],
        "recommendation_rule": policy["recommendation_rule"],
        "sealed_final_evaluation_input": False,
        "fair_benchmark_score_input": False,
    }
    _write_json_exclusive(Path(output_path), registry)
    return registry


def _materializer(proposal: dict[str, Any], dependencies: tuple[str, ...]):
    if proposal["candidate_key"] == "hbv_lite":
        return partial(materialize_hbv_lite_candidate, dependencies=dependencies)
    return partial(
        materialize_reference_candidate,
        category=proposal["candidate_key"],
        dependencies=dependencies,
    )


def validate_candidate_result(candidate_result: dict[str, Any], *, expected_basin_count: int) -> int:
    """Require one complete four-process, two-protocol candidate result and return denials."""
    expected_counts = {
        "basin_count": expected_basin_count,
        "protocol_count": 2,
        "registered_run_count": 4,
        "score_report_count": 2,
        "cell_count": expected_basin_count,
    }
    if any(candidate_result.get(name) != expected for name, expected in expected_counts.items()):
        raise RuntimeError("candidate rehearsal result cardinality mismatch")
    protocols = candidate_result.get("protocols")
    if not isinstance(protocols, dict) or set(protocols) != {"forward", "reverse"}:
        raise RuntimeError("candidate rehearsal protocols are incomplete")
    total_denials = 0
    for protocol in ("forward", "reverse"):
        for mode in ("train", "predict"):
            record = protocols[protocol].get(mode)
            if not isinstance(record, dict):
                raise RuntimeError("candidate registered-process record is missing")
            denials = record.get("denied_event_count")
            if not isinstance(denials, int) or isinstance(denials, bool) or denials < 0:
                raise RuntimeError("candidate denied-event count is invalid")
            total_denials += denials
            if denials:
                raise RuntimeError("candidate registered process contains a denied event")
            if (
                record.get("status") != "succeeded"
                or record.get("process_exit_code") != 0
                or record.get("normalized_exit_code") != 0
            ):
                raise RuntimeError("candidate registered process did not succeed cleanly")
    cells = candidate_result.get("cells")
    if not isinstance(cells, list) or len(cells) != expected_basin_count:
        raise RuntimeError("candidate development cells are incomplete")
    if any(
        not isinstance(cell, dict)
        or any(
            not isinstance(cell.get(name), (int, float))
            or isinstance(cell.get(name), bool)
            or not math.isfinite(float(cell[name]))
            for name in ("forward_nse", "reverse_nse", "mean_nse")
        )
        for cell in cells
    ):
        raise RuntimeError("candidate development metrics are not finite")
    return total_denials


def validate_candidate_runtime_evidence(
    candidate_root: str | Path, candidate_result: dict[str, Any]
) -> int:
    """Recount denials and output-contract gates from each raw registered-process log."""
    root = Path(candidate_root)
    total_denials = 0
    for protocol in ("forward", "reverse"):
        protocol_result = candidate_result["protocols"][protocol]
        for mode in ("train", "predict"):
            run_root = root / protocol_result[f"{mode}_run_root"]
            log_root = run_root / "logs"
            raw_result = json.loads((log_root / "runtime-result.json").read_text(encoding="utf-8"))
            if (
                raw_result.get("status") != "succeeded"
                or raw_result.get("process_exit_code") != 0
                or raw_result.get("normalized_exit_code") != 0
            ):
                raise RuntimeError("raw registered-process result did not succeed cleanly")
            if (
                raw_result.get("required_outputs_complete") is not True
                or not isinstance(raw_result.get("output_contract"), dict)
                or raw_result["output_contract"].get("valid") is not True
                or raw_result["output_contract"].get("failures") != []
            ):
                raise RuntimeError("raw registered-process output contract is incomplete")
            access_events = [
                json.loads(line)
                for line in (log_root / "access.jsonl").read_text(encoding="utf-8").splitlines()
                if line
            ]
            raw_denials = sum(event.get("decision") == "deny" for event in access_events)
            declared_denials = raw_result.get("denied_event_count")
            summarized_denials = protocol_result[mode].get("denied_event_count")
            if raw_denials != declared_denials or raw_denials != summarized_denials:
                raise RuntimeError("raw and summarized denied-event counts differ")
            if raw_denials:
                raise RuntimeError("raw registered-process access log contains a denied event")
            total_denials += raw_denials
    return total_denials


def _rank(candidate_results: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for result in candidate_results.values():
        metric = float(statistics.median(float(cell["mean_nse"]) for cell in result["cells"]))
        rows.append(
            {
                "candidate_id": result["candidate_id"],
                "category": result["category"],
                "median_mean_nse": metric,
            }
        )
    rows.sort(key=lambda item: (-item["median_mean_nse"], item["candidate_id"]))
    for index, row in enumerate(rows, start=1):
        row["rank"] = index
        row["recommended_for_64_basin_validation"] = index == 1
    return rows


def run_automatic_rehearsal(
    *,
    repo_root: str | Path,
    package_root: str | Path,
    expected_package_manifest_sha256: str,
    policy_path: str | Path,
    output_root: str | Path,
    resource_snapshot: ResourceSnapshot,
    candidate_dependencies: tuple[str, ...] = PINNED_DEPENDENCIES,
    monitor_sample_interval_seconds: float | None = None,
    monitor_reason: str | None = None,
) -> dict[str, Any]:
    """Run exactly three preregistered proposals and recommend at most one from development data."""
    policy = load_and_validate_rehearsal_policy(policy_path)
    repo = Path(repo_root).resolve()
    if not (repo / ".git").exists():
        raise ValueError("automatic rehearsal requires a Git repository root")
    packages = _inside(repo, package_root)
    _, package_manifest = _validate_package(packages, expected_package_manifest_sha256)
    basins = [str(basin).zfill(8) for basin in package_manifest["basins"]]
    frozen_basins = json.loads(SELECTION_PATH.read_text(encoding="utf-8"))["basins"]
    if basins != frozen_basins:
        raise ValueError("automatic rehearsal requires the exact frozen eight-basin package")
    root = _inside(repo, output_root)
    if root.exists():
        raise FileExistsError(root)
    proposal_registry_path = root / "PROPOSAL_REGISTRY.json"
    proposal_registry = freeze_rehearsal_proposals(policy_path, proposal_registry_path)

    candidate_results: dict[str, dict[str, Any]] = {}
    total_denials = 0
    for proposal in policy["proposals"]:
        key = proposal["candidate_key"]
        candidate_root = root / "candidates" / key
        result = run_single_candidate_development(
            repo_root=repo,
            package_root=packages,
            expected_package_manifest_sha256=expected_package_manifest_sha256,
            materialize=_materializer(proposal, candidate_dependencies),
            output_root=candidate_root,
            resource_snapshot=resource_snapshot,
            monitor_sample_interval_seconds=monitor_sample_interval_seconds,
            monitor_reason=monitor_reason,
        )
        if result.get("candidate_id") != proposal["candidate_id"] or result.get("category") != proposal["category"]:
            raise RuntimeError("materialized candidate identity differs from the frozen proposal")
        validate_candidate_result(result, expected_basin_count=len(basins))
        total_denials += validate_candidate_runtime_evidence(candidate_root, result)
        candidate_results[key] = result

    ranking = _rank(candidate_results)
    if len(ranking) != 3 or sum(row["recommended_for_64_basin_validation"] for row in ranking) > 1:
        raise RuntimeError("automatic rehearsal recommendation cardinality mismatch")
    candidate_summaries = {
        key: {
            "candidate_id": result["candidate_id"],
            "category": result["category"],
            "candidate_root": (root / "candidates" / key).relative_to(root).as_posix(),
            "summary_path": (
                root / "candidates" / key / "CANDIDATE_SUMMARY.json"
            ).relative_to(root).as_posix(),
            "summary_sha256": _sha256_file(
                root / "candidates" / key / "CANDIDATE_SUMMARY.json"
            ),
        }
        for key, result in candidate_results.items()
    }
    result = {
        "schema_version": "automatic_rehearsal_v1",
        "policy_sha256": proposal_registry["policy_sha256"],
        "proposal_registry_path": proposal_registry_path.relative_to(root).as_posix(),
        "proposal_registry_sha256": _sha256_file(proposal_registry_path),
        "package_manifest_sha256": expected_package_manifest_sha256,
        "source_manifest_sha256": package_manifest["source_manifest_sha256"],
        "basin_count": len(basins),
        "candidate_count": len(candidate_results),
        "protocol_count": 2,
        "registered_run_count": sum(item["registered_run_count"] for item in candidate_results.values()),
        "score_report_count": sum(item["score_report_count"] for item in candidate_results.values()),
        "protocol_basin_metric_count": len(candidate_results) * len(basins) * 2,
        "cell_count": sum(item["cell_count"] for item in candidate_results.values()),
        "total_denied_event_count": total_denials,
        "independent_monitor_enabled": monitor_sample_interval_seconds is not None,
        "monitor_sample_interval_seconds": monitor_sample_interval_seconds,
        "candidates": candidate_summaries,
        "ranking": ranking,
        "recommendation_rule": policy["recommendation_rule"],
        "recommended_candidate_id": ranking[0]["candidate_id"] if ranking else None,
        "artifact_manifest": _artifact_manifest(root),
        "sealed_final_evaluation_read_or_scored": False,
        "fair_benchmark_scoring_program_run": False,
        "formal_basin_search_run": False,
        "baseline_outperformance_claimed": False,
    }
    _write_json_exclusive(root / "REHEARSAL_SUMMARY.json", result)
    return result
