import hashlib
import json
from pathlib import Path
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
REPO_SRC = IDEA_ROOT.parent
sys.path.insert(0, str(REPO_SRC))
sys.path.insert(0, str(IDEA_ROOT))

from fair_benchmark.ledger import append_attempt, read_rows  # noqa: E402
from fair_benchmark.postseal_holdout_v09 import (  # noqa: E402
    derive_postseal_holdout_v09,
    public_partition_summary,
)

import audit_clean_pair_score_final_v09 as final_audit  # noqa: E402


HASHES = {
    "baseline": "a" * 64,
    "capacity_control": "b" * 64,
    "challenger": "c" * 64,
}
PROTOCOL_SHA = "d" * 64
GATE = {
    "min_effect": 0.01,
    "max_wilcoxon_p": 0.05,
    "bootstrap_samples": 10000,
    "bootstrap_seed": 0,
    "ci_low_must_exceed": 0.0,
    "holdout_min_effect": 0.005,
    "holdout_retention": 0.5,
}


def _canonical_sha256(value: dict) -> str:
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False),
        encoding="utf-8",
    )


def _case(tmp_path: Path) -> dict:
    basin_ids = [f"{index:08d}" for index in range(531)]
    basin_path = tmp_path / "basins.txt"
    basin_path.write_text("".join(f"{basin}\n" for basin in basin_ids), encoding="utf-8")
    bundle = {
        "contract_id": "S09C-CLEAN-PAIR",
        "track_id": "track0_forcing_only_clean_v09",
        "contract_sha256": "e" * 64,
        "bundle_sha256": "f" * 64,
        "protocol_sha256": PROTOCOL_SHA,
        "prediction_seal_sha256": "1" * 64,
        "source_bundle": {
            "status": "complete_source_bundle",
            "scan_hits": 0,
            "tree_sha256": "3" * 64,
        },
        "predictions": {
            role: {"sha256": digest}
            for role, digest in HASHES.items()
        },
        "postseal_holdout": {
            "method": "postseal_nonce_sha256_rank_v1",
            "status": "awaiting_authorized_nonce_draw",
            "holdout_count": 107,
            "public_count": 424,
        },
    }
    authorization = {
        "status": "authorized_clean_pair_score",
        "contract_sha256": bundle["contract_sha256"],
        "bundle_sha256": bundle["bundle_sha256"],
        "prediction_sha256": HASHES,
        "prediction_seal_sha256": bundle["prediction_seal_sha256"],
        "source_tree": {
            "git_head": "4" * 40,
            "tree_sha256": "5" * 64,
            "files": {"fair_benchmark/score_clean_pair_v09.py": "6" * 64},
        },
        "trusted_frozen_inputs": {
            "basins": {
                "relative_path": basin_path.name,
                "sha256": _sha256(basin_path),
            }
        },
        "allowed_experiment_id": "S09C-CLEAN-PAIR",
        "allowed_track_id": "track0_forcing_only_clean_v09",
        "maximum_attempts": 1,
    }
    auth_path = tmp_path / "authorization.json"
    _write(auth_path, authorization)
    consumption = {
        "status": "consumed_no_retry",
        "authorization_sha256": _canonical_sha256(authorization),
        "maximum_attempts": 1,
        "retry_allowed": False,
    }
    consumption_path = tmp_path / "consumption.json"
    _write(consumption_path, consumption)
    partition = derive_postseal_holdout_v09(
        basin_ids,
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=HASHES,
        nonce_hex="2" * 64,
        holdout_count=107,
    )
    draw = {
        "status": "complete_single_holdout_draw",
        "consumption_file_sha256": _sha256(consumption_path),
        "consumption_canonical_sha256": _canonical_sha256(consumption),
        "contract_sha256": bundle["contract_sha256"],
        "bundle_sha256": bundle["bundle_sha256"],
        "prediction_sha256": HASHES,
        "nonce_hex": "2" * 64,
        **public_partition_summary(partition),
        "nonce_draw_count": 1,
        "nonce_redraw_count": 0,
    }
    draw_path = tmp_path / "draw.json"
    _write(draw_path, draw)
    bundle_path = tmp_path / "bundle.json"
    _write(bundle_path, bundle)

    public = {
        "n": 424,
        "median_paired_delta": 0.02,
        "wilcoxon_p": 0.001,
        "ci_low": 0.01,
        "ci_high": 0.03,
        "challenger_median": 0.78,
        "baseline_median": 0.76,
    }
    holdout = {
        "n": 107,
        "median_paired_delta": 0.015,
        "wilcoxon_p": 0.01,
        "ci_low": 0.005,
        "ci_high": 0.025,
        "challenger_median": 0.775,
        "baseline_median": 0.76,
    }
    ledger_path = tmp_path / "ledger.csv"
    append_attempt(
        ledger_path,
        {
            "timestamp": "2026-07-31T00:00:00+08:00",
            "experiment_id": "S09C-CLEAN-PAIR",
            "track": "track0_forcing_only_clean_v09",
            "verdict": "PASS",
            "median_paired_delta": public["median_paired_delta"],
            "wilcoxon_p": public["wilcoxon_p"],
            "n": public["n"],
            "challenger_median": public["challenger_median"],
            "baseline_median": public["baseline_median"],
            "predictions_sha": HASHES["challenger"],
        },
    )
    row = read_rows(ledger_path)[0]
    report = {
        "contract_id": "S09C-CLEAN-PAIR",
        "track": "track0_forcing_only_clean_v09",
        "verdict": "PASS",
        "reasons": ["significant_win_holdout_consistent"],
        "primary": {
            "baseline_id": "B09-CLASSIC",
            "challenger_id": "E09-CONTINUOUS",
            "gate": GATE,
            "public": public,
            "holdout": holdout,
            "coverage_ok": True,
            "leakage_hits": 0,
            "leakage_detail": [],
            "contract_ok": True,
        },
        "capacity_comparison": {
            "baseline_id": "B09-CAPACITY",
            "challenger_id": "E09-CONTINUOUS",
            "verdict_role": "descriptive_only",
            "may_affect_primary_verdict": False,
            "public": dict(public, median_paired_delta=0.01),
            "holdout": dict(holdout, median_paired_delta=0.008),
        },
        "historical_reference": {
            "status": "historical_reference_nonqualifying",
            "median_nse": 0.759225,
            "qualifying": False,
            "may_affect_verdict": False,
        },
        "provenance": {
            "contract_sha256": bundle["contract_sha256"],
            "bundle_sha256": bundle["bundle_sha256"],
            "prediction_seal_sha256": bundle["prediction_seal_sha256"],
            "prediction_sha256": HASHES,
            "basin_file_sha256": _sha256(basin_path),
            "holdout_draw_receipt_sha256": _canonical_sha256(draw),
            "nonce_sha256": partition["nonce_sha256"],
            "partition_salt_sha256": partition["partition_salt_sha256"],
            "holdout_set_sha256": partition["holdout_set_sha256"],
            "authorization_sha256": _canonical_sha256(authorization),
            "consumption_file_sha256": _sha256(consumption_path),
            "consumption_canonical_sha256": _canonical_sha256(consumption),
            "trusted_source_tree_sha256": authorization["source_tree"]["tree_sha256"],
            "candidate_source_tree_sha256": bundle["source_bundle"]["tree_sha256"],
        },
        "ledger": {
            "before": {"row_count": 0, "sha256": None, "last_row_hash": None},
            "after": {
                "row_count": 1,
                "sha256": _sha256(ledger_path),
                "last_row_hash": row["row_hash"],
            },
            "new_row_hash": row["row_hash"],
        },
        "score_submission_call_count": 1,
        "ledger_append_count": 1,
    }
    report_path = tmp_path / "report.json"
    _write(report_path, report)
    return {
        "report": report_path,
        "authorization": auth_path,
        "consumption": consumption_path,
        "draw": draw_path,
        "bundle": bundle_path,
        "basins": basin_path,
        "ledger": ledger_path,
        "report_payload": report,
    }


def _audit(case: dict) -> dict:
    return final_audit.audit_clean_pair_score_final_v09(
        case["report"],
        case["authorization"],
        case["consumption"],
        case["draw"],
        case["bundle"],
        case["basins"],
        case["ledger"],
    )


def test_final_audit_uses_only_report_ledger_and_hashes(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(
        "fair_benchmark.score.score_submission",
        lambda **_: (_ for _ in ()).throw(AssertionError("rescoring forbidden")),
    )
    result = _audit(case)
    assert result["status"] == "PASS"
    assert result["score_submission_call_count"] == 1
    assert result["ledger_rows_added"] == 1
    assert result["answer_reopened"] is False
    assert result["prediction_values_opened"] is False
    assert result["capacity_comparison_descriptive"] is True


def test_final_audit_missing_report_is_incomplete_and_nonretryable(tmp_path):
    case = _case(tmp_path)
    case["report"].unlink()
    result = _audit(case)
    assert result["status"] == "HOLD_INCOMPLETE_NO_RETRY"
    assert result["retry_allowed"] is False


@pytest.mark.parametrize("tamper", ("ledger", "draw", "consumption_binding", "leak"))
def test_final_audit_rejects_integrity_drift_or_sensitive_output(tmp_path, tamper):
    case = _case(tmp_path)
    if tamper == "ledger":
        case["ledger"].write_text("broken\n", encoding="utf-8")
    elif tamper == "draw":
        draw = json.loads(case["draw"].read_text(encoding="utf-8"))
        draw["holdout_set_sha256"] = "9" * 64
        _write(case["draw"], draw)
    elif tamper == "consumption_binding":
        draw = json.loads(case["draw"].read_text(encoding="utf-8"))
        draw["consumption_file_sha256"] = "9" * 64
        _write(case["draw"], draw)
    else:
        report = json.loads(case["report"].read_text(encoding="utf-8"))
        report["holdout_ids"] = ["00000000"]
        _write(case["report"], report)
    result = _audit(case)
    assert result["status"] == "REJECT"
    assert result["errors"]


def test_final_audit_module_has_no_rescoring_import_or_call():
    source = (IDEA_ROOT / "audit_clean_pair_score_final_v09.py").read_text(encoding="utf-8")
    assert "load_" + "obs_csv" not in source
    assert "score_" + "submission" not in source
    assert "score_" + "clean_pair_core_v09" not in source
