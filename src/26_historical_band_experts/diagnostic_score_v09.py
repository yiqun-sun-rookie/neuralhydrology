"""Diagnostic (non-qualifying) scoring of the formal version-09 ensembles.

This is deliberately NOT the clean-pair route. It exists to answer one question for a
go/no-go decision: how large is the parameter-matched effect of the continuous history
representation on the evaluation period?

What this module does not do, by construction:

* it never consumes the one-call clean-pair score authorization;
* it never draws the post-seal holdout nonce and never partitions 424/107;
* it never appends to the score ledger;
* it never writes into the sealed training results or the predictions directory.

Every report it writes is stamped ``diagnostic_only`` and ``qualifying: false``. A verdict
produced here cannot be presented as the pre-registered outcome, and running it forfeits
the observation-blind status that the clean-pair route depends on. That trade-off is a
decision for the operator, not for this module.
"""
from __future__ import annotations

from collections.abc import Mapping
import argparse
import json
import os
from pathlib import Path

import numpy as np

IDEA_ROOT = Path(__file__).resolve().parent
import sys

if str(IDEA_ROOT) not in sys.path:
    sys.path.insert(0, str(IDEA_ROOT))
WORKTREE_SRC = IDEA_ROOT.parent
if str(WORKTREE_SRC) not in sys.path:
    sys.path.insert(0, str(WORKTREE_SRC))

from artifact_v09 import canonical_sha256, sha256_file, write_json_atomic
from fair_benchmark.io import load_obs_csv, load_predictions
from fair_benchmark.metrics import per_basin_nse
from fair_benchmark.stats import paired_comparison

_ROLES = {
    "baseline": "B09-CLASSIC",
    "capacity_control": "B09-CAPACITY",
    "challenger": "E09-CONTINUOUS",
}
_ANSWER_KEY_SHA256 = "576d548253064699ade1e312ea875097d070557e3eef334874c310df61d8fd1e"
_PRIMARY_GATE = {
    "min_effect": 0.01,
    "max_wilcoxon_p": 0.05,
    "bootstrap_samples": 10_000,
    "bootstrap_seed": 0,
    "ci_low_must_exceed": 0.0,
}
_EXPECTED_BASINS = 531


class DiagnosticScoreError(RuntimeError):
    """Raised when a diagnostic comparison cannot be computed as specified."""


def _load_prediction_manifest(predictions_root: Path) -> dict:
    path = predictions_root / "manifest.json"
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise DiagnosticScoreError(f"invalid prediction manifest: {path}") from exc
    if manifest.get("status") != "formal_predictions_complete":
        raise DiagnosticScoreError("prediction manifest status drift")
    if manifest.get("formal_evaluation_observation_reads") != 0:
        raise DiagnosticScoreError("the prediction stage already reported reading observations")
    if manifest.get("official_score_called") is not False:
        raise DiagnosticScoreError("the prediction stage already reported an official score call")
    return manifest


def _ensemble_path(predictions_root: Path, family: str) -> Path:
    path = predictions_root / "ensembles" / f"{family}_ensemble.csv"
    if not path.is_file():
        raise DiagnosticScoreError(f"missing ensemble prediction: {path}")
    return path


def _median(values: Mapping[str, float]) -> float:
    finite = np.array([value for value in values.values() if np.isfinite(value)], dtype=np.float64)
    if finite.size == 0:
        raise DiagnosticScoreError("no finite per-basin score")
    return float(np.median(finite))


def _coverage(scores: Mapping[str, float]) -> dict:
    finite = sum(1 for value in scores.values() if np.isfinite(value))
    return {"basins": len(scores), "finite": finite, "nonfinite": len(scores) - finite}


def diagnostic_compare_v09(
    predictions_root: str | Path,
    answer_key: str | Path,
    *,
    require_answer_key_hash: bool = True,
    require_formal_geometry: bool = True,
) -> dict:
    """Score the three ensembles against the held answer key and compare the main pair."""
    predictions_root = Path(os.path.abspath(predictions_root)).resolve()
    answer_key = Path(os.path.abspath(answer_key)).resolve()
    if not answer_key.is_file():
        raise DiagnosticScoreError(f"answer key is missing: {answer_key}")
    answer_key_sha256 = sha256_file(answer_key)
    if require_answer_key_hash and answer_key_sha256 != _ANSWER_KEY_SHA256:
        raise DiagnosticScoreError(
            f"answer key hash drift: {answer_key_sha256} != {_ANSWER_KEY_SHA256}")
    manifest = _load_prediction_manifest(predictions_root)

    observations = load_obs_csv(answer_key)
    if require_formal_geometry and len(observations) != _EXPECTED_BASINS:
        raise DiagnosticScoreError(f"answer key basin count drift: {len(observations)}")

    scores = {}
    prediction_bindings = {}
    for role, family in _ROLES.items():
        path = _ensemble_path(predictions_root, family)
        prediction_bindings[role] = {
            "family": family,
            "relative_path": f"ensembles/{family}_ensemble.csv",
            "sha256": sha256_file(path),
        }
        scores[role] = per_basin_nse(observations, load_predictions(path))

    primary = paired_comparison(
        scores["challenger"],
        scores["capacity_control"],
        n_bootstrap=_PRIMARY_GATE["bootstrap_samples"],
        seed=_PRIMARY_GATE["bootstrap_seed"],
    )
    descriptive = paired_comparison(
        scores["challenger"],
        scores["baseline"],
        n_bootstrap=_PRIMARY_GATE["bootstrap_samples"],
        seed=_PRIMARY_GATE["bootstrap_seed"],
    )
    capacity_versus_baseline = paired_comparison(
        scores["capacity_control"],
        scores["baseline"],
        n_bootstrap=_PRIMARY_GATE["bootstrap_samples"],
        seed=_PRIMARY_GATE["bootstrap_seed"],
    )

    gate_checks = {
        "effect_at_least_min": bool(primary["median_paired_delta"] >= _PRIMARY_GATE["min_effect"]),
        "wilcoxon_below_max": bool(
            np.isfinite(primary["wilcoxon_p"]) and primary["wilcoxon_p"] < _PRIMARY_GATE["max_wilcoxon_p"]),
        "ci_low_above_zero": bool(primary["ci_low"] > _PRIMARY_GATE["ci_low_must_exceed"]),
    }
    report = {
        "schema": "historical_multiscale_formal_v09_diagnostic_score_v1",
        "status": "diagnostic_score_complete",
        "diagnostic_only": True,
        "qualifying": False,
        "verdict_authority": "none_this_is_not_the_preregistered_clean_pair_route",
        "roles": dict(_ROLES),
        "answer_key": {"path": str(answer_key), "sha256": answer_key_sha256},
        "prediction_bindings": prediction_bindings,
        "prediction_manifest_sha256": sha256_file(predictions_root / "manifest.json"),
        "prediction_run_order_canonical_sha256": manifest.get("run_order_canonical_sha256"),
        "median_nse": {role: _median(values) for role, values in scores.items()},
        "coverage": {role: _coverage(values) for role, values in scores.items()},
        "primary_comparison_challenger_vs_capacity": primary,
        "descriptive_challenger_vs_classic": descriptive,
        "descriptive_capacity_vs_classic": capacity_versus_baseline,
        "primary_gate_reference": dict(_PRIMARY_GATE),
        "primary_gate_checks": gate_checks,
        "all_primary_gate_checks_pass": all(gate_checks.values()),
        "postseal_holdout_drawn": False,
        "score_ledger_appended": False,
        "official_score_called": False,
        "one_call_authorization_consumed": False,
    }
    report["report_sha256"] = canonical_sha256({k: v for k, v in report.items() if k != "report_sha256"})
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--predictions-root", required=True)
    parser.add_argument("--answer-key", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--allow-answer-key-hash-drift", action="store_true")
    args = parser.parse_args(argv)
    report = diagnostic_compare_v09(
        args.predictions_root,
        args.answer_key,
        require_answer_key_hash=not args.allow_answer_key_hash_drift,
    )
    output = Path(os.path.abspath(args.output))
    output.parent.mkdir(parents=True, exist_ok=True)
    write_json_atomic(output, report)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
