import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest

from fair_benchmark import score_clean_pair_v09
from fair_benchmark.ledger import append_attempt, count_attempts, read_rows
from fair_benchmark.clean_pair_authorization_v09 import clean_pair_ledger_snapshot_v09
from fair_benchmark.postseal_holdout_v09 import (
    derive_postseal_holdout_v09,
    public_partition_summary,
)
from fair_benchmark.score_clean_pair_v09 import (
    CleanPairScoreError,
    score_clean_pair_core_v09,
)


_REPO_ROOT = Path(__file__).resolve().parents[3]
_IDEA_ROOT = _REPO_ROOT / "src" / "26_historical_band_experts"
if str(_IDEA_ROOT) not in sys.path:
    sys.path.insert(0, str(_IDEA_ROOT))

from clean_pair_bundle_v09 import clean_pair_bundle_sha256  # noqa: E402


ROLES = {
    "baseline": "B09-CLASSIC",
    "capacity_control": "B09-CAPACITY",
    "challenger": "E09-CONTINUOUS",
}
PATHS = {
    "baseline": "predictions/ensembles/B09-CLASSIC_ensemble.csv",
    "capacity_control": "predictions/ensembles/B09-CAPACITY_ensemble.csv",
    "challenger": "predictions/ensembles/E09-CONTINUOUS_ensemble.csv",
}
PROTOCOL_SHA = "b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _canonical_sha256(value: dict) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _case(
    tmp_path: Path,
    *,
    zero_delta: bool = False,
    reverse_basin_file: bool = False,
) -> dict:
    basin_ids = [f"{index:08d}" for index in range(531)]
    if reverse_basin_file:
        basin_ids.reverse()
    dates = pd.date_range("2000-01-01", periods=4, freq="D")
    frozen_root = tmp_path / "frozen"
    frozen_root.mkdir()
    basin_path = frozen_root / "basins.txt"
    basin_path.write_text("".join(f"{basin}\n" for basin in basin_ids), encoding="utf-8")

    obs_rows = []
    prediction_rows = {role: [] for role in ROLES}
    for index, basin in enumerate(basin_ids):
        obs = np.asarray([0.0, 1.0, 2.0, 4.0], dtype=np.float64) + index * 0.001
        simulations = {
            "baseline": obs + 0.40,
            "capacity_control": obs + 0.20,
            "challenger": obs + (
                0.40
                if zero_delta
                else 0.03 + (int(basin) % 17) * 0.004
            ),
        }
        for date, value in zip(dates, obs):
            obs_rows.append({
                "basin": basin,
                "date": date.strftime("%Y-%m-%d"),
                "qobs": value,
            })
        for role, values in simulations.items():
            for date, value in zip(dates, values):
                prediction_rows[role].append({
                    "basin": basin,
                    "date": date.strftime("%Y-%m-%d"),
                    "qsim": value,
                })

    answer_path = frozen_root / "answer.csv"
    pd.DataFrame(obs_rows).to_csv(answer_path, index=False)
    prediction_root = tmp_path / "formal_v09"
    predictions = {}
    for role, relative_path in PATHS.items():
        path = prediction_root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(prediction_rows[role]).to_csv(path, index=False)
        predictions[role] = {
            "experiment_id": ROLES[role],
            "relative_path": relative_path,
            "sha256": _sha256(path),
            "row_count": 531 * 4,
            "basin_count": 531,
            "dates_per_basin": 4,
            "status": "exact_ordered_coverage",
        }

    source_bundle = tmp_path / "source_bundle"
    source_bundle.mkdir()
    (source_bundle / "model.py").write_text("def predict(x):\n    return x\n", encoding="utf-8")
    contract = {
        "contract_id": "S09C-CLEAN-PAIR",
        "track_id": "track0_forcing_only_clean_v09",
        "protocol_id": "P09-FORMAL",
        "protocol_sha256": PROTOCOL_SHA,
        "roles": ROLES,
        "ensemble_paths": PATHS,
        "trusted_frozen_inputs": {
            "answer_key": {
                "relative_path": answer_path.name,
                "sha256": _sha256(answer_path),
            },
            "basins": {
                "relative_path": basin_path.name,
                "sha256": _sha256(basin_path),
            },
        },
        "postseal_holdout": {
            "method": "postseal_nonce_sha256_rank_v1",
            "holdout_count": 107,
            "public_count": 424,
        },
        "primary_gate": {
            "min_effect": 0.01,
            "max_wilcoxon_p": 0.05,
            "bootstrap_samples": 10000,
            "bootstrap_seed": 0,
            "ci_low_must_exceed": 0.0,
            "holdout_min_effect": 0.005,
            "holdout_retention": 0.5,
        },
        "historical_reference": {
            "status": "historical_reference_nonqualifying",
            "qualifying": False,
            "may_affect_verdict": False,
        },
    }
    prediction_sha = {role: predictions[role]["sha256"] for role in ROLES}
    partition = derive_postseal_holdout_v09(
        basin_ids,
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=prediction_sha,
        nonce_hex="1" * 64,
        holdout_count=107,
    )
    draw_receipt = {
        "status": "complete_single_holdout_draw",
        "nonce_hex": "1" * 64,
        **public_partition_summary(partition),
        "prediction_sha256": prediction_sha,
        "nonce_draw_count": 1,
        "nonce_redraw_count": 0,
    }
    bundle = {
        "bundle_version": 1,
        "contract_id": "S09C-CLEAN-PAIR",
        "contract_sha256": _canonical_sha256(contract),
        "protocol_id": "P09-FORMAL",
        "protocol_sha256": PROTOCOL_SHA,
        "track_id": "track0_forcing_only_clean_v09",
        "prediction_seal_sha256": "d" * 64,
        "upstream_evidence": {"training_seal_sha256": "e" * 64},
        "source_bundle": {
            "status": "complete_source_bundle",
            "scan_hits": 0,
            "tree_sha256": "f" * 64,
        },
        "final_checkpoints": [],
        "predictions": predictions,
        "postseal_holdout": {
            "method": "postseal_nonce_sha256_rank_v1",
            "status": "awaiting_authorized_nonce_draw",
            "holdout_count": 107,
            "public_count": 424,
        },
        "status": "complete_clean_pair_bundle",
    }
    bundle["bundle_sha256"] = clean_pair_bundle_sha256(bundle)
    draw_receipt["contract_sha256"] = bundle["contract_sha256"]
    draw_receipt["bundle_sha256"] = bundle["bundle_sha256"]
    return {
        "contract": contract,
        "bundle": bundle,
        "draw_receipt": draw_receipt,
        "frozen_root": frozen_root,
        "prediction_root": prediction_root,
        "source_bundle": source_bundle,
        "basin_ids": basin_ids,
        "partition": partition,
    }


def _run(case: dict, ledger_path: Path) -> dict:
    return score_clean_pair_core_v09(
        contract=case["contract"],
        bundle=case["bundle"],
        holdout_draw_receipt=case["draw_receipt"],
        trusted_frozen_root=case["frozen_root"],
        prediction_root=case["prediction_root"],
        source_bundle=case["source_bundle"],
        ledger_path=ledger_path,
        authorized_ledger_snapshot=clean_pair_ledger_snapshot_v09(ledger_path),
        timestamp="2026-07-31T00:00:00",
    )


def test_clean_pair_service_calls_existing_scorer_once_and_logs_once(tmp_path, monkeypatch):
    case = _case(tmp_path)
    calls = {"count": 0, "track": None}
    real = score_clean_pair_v09.score_submission

    def counted(**kwargs):
        calls["count"] += 1
        calls["track"] = kwargs["track"]
        return real(**kwargs)

    monkeypatch.setattr(score_clean_pair_v09, "score_submission", counted)
    ledger = tmp_path / "ledger.csv"
    report = _run(case, ledger)

    assert calls["count"] == 1
    assert count_attempts(ledger) == 1
    assert report["track"] == "track0_forcing_only_clean_v09"
    assert report["primary"]["baseline_id"] == "B09-CLASSIC"
    assert report["capacity_comparison"]["verdict_role"] == "descriptive_only"
    assert report["historical_reference"]["qualifying"] is False
    assert calls["track"].secret_holdout == case["partition"]["holdout_ids"]
    assert report["score_submission_call_count"] == 1
    assert report["ledger_append_count"] == 1
    assert report["primary"]["public"]["n"] == 424
    assert report["primary"]["holdout"]["n"] == 107
    assert "holdout_ids" not in json.dumps(report)
    assert "per_basin" not in json.dumps(report)
    json.dumps(report, allow_nan=False)


def test_partition_receipt_drift_fails_before_answer_is_loaded(tmp_path, monkeypatch):
    case = _case(tmp_path)
    case["draw_receipt"]["holdout_set_sha256"] = "f" * 64
    calls = {"count": 0}
    real = score_clean_pair_v09.load_obs_csv

    def counted(path):
        calls["count"] += 1
        return real(path)

    monkeypatch.setattr(score_clean_pair_v09, "load_obs_csv", counted)
    with pytest.raises(CleanPairScoreError, match="holdout"):
        _run(case, tmp_path / "ledger.csv")
    assert calls["count"] == 0
    assert count_attempts(tmp_path / "ledger.csv") == 0


def test_zero_paired_difference_produces_strict_json_and_one_ledger_row(tmp_path):
    case = _case(tmp_path, zero_delta=True)
    ledger = tmp_path / "ledger.csv"
    report = _run(case, ledger)
    assert report["primary"]["public"]["wilcoxon_p"] is None
    assert report["primary"]["public"]["wilcoxon_p_reason"] == "all_paired_differences_zero"
    assert report["verdict"] == "HOLD"
    assert count_attempts(ledger) == 1
    json.dumps(report, allow_nan=False)


def test_source_bundle_forbidden_access_forces_hold(tmp_path):
    case = _case(tmp_path)
    (case["source_bundle"] / "model.py").write_text(
        "path = 'data/camels_us/usgs_streamflow/file.txt'\n",
        encoding="utf-8",
    )
    report = _run(case, tmp_path / "ledger.csv")
    assert report["verdict"] == "HOLD"
    assert report["primary"]["leakage_hits"] >= 1


def test_precomputed_bootstrap_uses_existing_scorer_basin_order(tmp_path):
    case = _case(tmp_path, reverse_basin_file=True)
    report = _run(case, tmp_path / "ledger.csv")
    assert report["score_submission_call_count"] == 1
    assert report["primary"]["public"]["n"] == 424
    assert report["primary"]["holdout"]["n"] == 107


def test_ledger_change_during_metric_computation_burns_no_clean_pair_row(tmp_path, monkeypatch):
    case = _case(tmp_path)
    ledger = tmp_path / "ledger.csv"
    real_load = score_clean_pair_v09.load_predictions
    calls = {"count": 0}

    def mutate_ledger_after_read(path):
        result = real_load(path)
        calls["count"] += 1
        if calls["count"] == 1:
            append_attempt(
                ledger,
                {
                    "timestamp": "2026-07-31T00:00:01+08:00",
                    "experiment_id": "OTHER-SCORE",
                    "track": "other",
                    "verdict": "HOLD",
                },
            )
        return result

    monkeypatch.setattr(score_clean_pair_v09, "load_predictions", mutate_ledger_after_read)
    with pytest.raises(CleanPairScoreError, match="ledger changed during metric"):
        _run(case, ledger)
    assert all(row.get("experiment_id") != "S09C-CLEAN-PAIR" for row in read_rows(ledger))


def test_one_attempt_entry_has_one_existing_scorer_call_and_fail_closed_order():
    source = Path(score_clean_pair_v09.__file__).read_text(encoding="utf-8")
    assert source.count("score_" + "submission(") == 1
    run_body = source.split("def run_clean_pair_score_once_v09(", 1)[1]
    consume = run_body.index("consume_clean_pair_score_authorization_v09(")
    draw = run_body.index("draw_holdout_nonce_once_v09(")
    score = run_body.index("report = score_clean_pair_core_v09(")
    persist = run_body.index("_exclusive_atomic_report(")
    assert consume < draw < score < persist
    assert 'parser.add_argument("--execution-task-id", required=True)' in run_body


@pytest.mark.parametrize(
    "field",
    ("ledger_path", "consumption_path", "draw_path", "out_path"),
)
def test_one_attempt_entry_rejects_any_alternate_mutable_path(tmp_path, field):
    worktree_src = Path(score_clean_pair_v09.__file__).resolve().parents[1]
    worktree_root = worktree_src.parent
    formal_root = worktree_root / "results" / "26_historical_band_experts" / "formal_v09"
    paths = {
        "worktree_src": worktree_src,
        "authorized_output_root": (
            "results/26_historical_band_experts/formal_v09/clean_pair_score_attempt_01"
        ),
        "contract_path": (
            worktree_src
            / "26_historical_band_experts"
            / "configs"
            / "formal_v09_clean_pair_scoring_contract.json"
        ),
        "bundle_path": formal_root / "predictions" / "clean_pair_bundle.json",
        "authorization_path": (
            formal_root / "authorizations" / "clean_pair_scoring_authorization.json"
        ),
        "prediction_root": formal_root,
        "source_bundle": formal_root / "predictions" / "source_bundle",
        "ledger_path": worktree_src / "fair_benchmark" / "registry" / "portfolio_ledger.csv",
        "consumption_path": formal_root / "clean_pair_scoring_authorization_consumed.json",
        "draw_path": formal_root / "clean_pair_holdout_draw_receipt.json",
        "out_path": formal_root / "clean_pair_score_attempt_01" / "report.json",
    }
    canonical = score_clean_pair_v09._validate_authorized_score_paths_v09(**paths)
    assert canonical["out"].endswith("clean_pair_score_attempt_01\\report.json")
    with pytest.raises(CleanPairScoreError, match="noncanonical"):
        score_clean_pair_v09._validate_authorized_score_paths_v09(
            **dict(paths, **{field: tmp_path / f"alternate_{field}"})
        )


@pytest.mark.parametrize("role", ("baseline", "capacity_control", "challenger"))
def test_prediction_hash_drift_fails_without_ledger_append(tmp_path, role):
    case = _case(tmp_path)
    case["bundle"]["predictions"][role]["sha256"] = "f" * 64
    case["bundle"]["bundle_sha256"] = clean_pair_bundle_sha256(case["bundle"])
    ledger = tmp_path / "ledger.csv"
    with pytest.raises(CleanPairScoreError, match="prediction"):
        _run(case, ledger)
    assert count_attempts(ledger) == 0
