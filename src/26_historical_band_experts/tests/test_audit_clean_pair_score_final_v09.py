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
        "status": "complete_clean_pair_bundle",
    }
    bundle["bundle_sha256"] = _canonical_sha256(bundle)
    empty_ledger_snapshot = {
        "row_count": 0,
        "sha256": hashlib.sha256(b"").hexdigest(),
        "last_row_hash": "GENESIS",
        "experiment_id_count": 0,
        "chain_breaks": 0,
    }
    authorization = {
        "status": "authorized_clean_pair_score",
        "approval": {
            "text": "synthetic",
            "utf8_sha256": hashlib.sha256(b"synthetic").hexdigest(),
            "task_id": "approval-task",
            "approved_at": "2026-07-31T00:00:00+08:00",
        },
        "contract_sha256": bundle["contract_sha256"],
        "bundle_sha256": bundle["bundle_sha256"],
        "prediction_sha256": HASHES,
        "prediction_seal_sha256": bundle["prediction_seal_sha256"],
        "source_tree": {
            "git_head": "4" * 40,
            "files": {"fair_benchmark/score_clean_pair_v09.py": "6" * 64},
        },
        "trusted_frozen_inputs": {
            "answer_key": {
                "relative_path": "answer.parquet",
                "sha256": "7" * 64,
            },
            "basins": {
                "relative_path": basin_path.name,
                "sha256": _sha256(basin_path),
            }
        },
        "allowed_experiment_id": "S09C-CLEAN-PAIR",
        "allowed_track_id": "track0_forcing_only_clean_v09",
        "ledger_snapshot": empty_ledger_snapshot,
        "maximum_attempts": 1,
    }
    authorization["source_tree"]["tree_sha256"] = _canonical_sha256(
        authorization["source_tree"]["files"]
    )
    auth_path = tmp_path / "authorization.json"
    _write(auth_path, authorization)
    module_paths = {
        "fair_benchmark.score_clean_pair_v09": str(
            (REPO_SRC / "fair_benchmark" / "score_clean_pair_v09.py").resolve()
        )
    }
    consumption = {
        "status": "consumed_no_retry",
        "authorization_sha256": _canonical_sha256(authorization),
        "maximum_attempts": 1,
        "retry_allowed": False,
        "launch_snapshot": {
            "task_id": "independent-score-task",
            "module_import_probe": {
                "clean_subprocess": module_paths,
                "live_process": module_paths,
                "paths_sha256": _canonical_sha256(module_paths),
            },
        },
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
        "win_rate": 0.7,
    }
    holdout = {
        "n": 107,
        "median_paired_delta": 0.015,
        "wilcoxon_p": 0.01,
        "ci_low": 0.005,
        "ci_high": 0.025,
        "challenger_median": 0.775,
        "baseline_median": 0.76,
        "win_rate": 0.65,
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
            "finite_metric_coverage": {
                "baseline": True,
                "capacity_control": True,
                "challenger": True,
            },
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
            "answer_key_sha256": authorization["trusted_frozen_inputs"]["answer_key"]["sha256"],
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
            "module_import_paths_sha256": (
                consumption["launch_snapshot"]["module_import_probe"]["paths_sha256"]
            ),
            "execution_task_id": consumption["launch_snapshot"]["task_id"],
        },
        "ledger": {
            "before": {
                "row_count": empty_ledger_snapshot["row_count"],
                "sha256": empty_ledger_snapshot["sha256"],
                "last_row_hash": empty_ledger_snapshot["last_row_hash"],
            },
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
        require_canonical_paths=False,
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


def test_final_audit_rejects_cloned_noncanonical_artifact_paths(tmp_path):
    case = _case(tmp_path)
    result = final_audit.audit_clean_pair_score_final_v09(
        case["report"],
        case["authorization"],
        case["consumption"],
        case["draw"],
        case["bundle"],
        case["basins"],
        case["ledger"],
    )
    assert result["status"] == "REJECT"
    assert "noncanonical" in result["errors"][0]


@pytest.mark.parametrize(
    "tamper",
    (
        "ledger",
        "draw",
        "consumption_binding",
        "provenance",
        "bundle_hash",
        "gate",
        "leak",
    ),
)
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
    elif tamper == "provenance":
        report = json.loads(case["report"].read_text(encoding="utf-8"))
        report["provenance"]["answer_key_sha256"] = "9" * 64
        _write(case["report"], report)
    elif tamper == "bundle_hash":
        bundle = json.loads(case["bundle"].read_text(encoding="utf-8"))
        bundle["bundle_sha256"] = "9" * 64
        _write(case["bundle"], bundle)
    elif tamper == "gate":
        report = json.loads(case["report"].read_text(encoding="utf-8"))
        report["primary"]["gate"]["min_effect"] = -1.0
        _write(case["report"], report)
    else:
        report = json.loads(case["report"].read_text(encoding="utf-8"))
        report["basin_metrics"] = [0.5] * 531
        _write(case["report"], report)
    result = _audit(case)
    assert result["status"] == "REJECT"
    assert result["errors"]


def test_final_audit_module_has_no_rescoring_import_or_call():
    source = (IDEA_ROOT / "audit_clean_pair_score_final_v09.py").read_text(encoding="utf-8")
    assert "load_" + "obs_csv" not in source
    assert "score_" + "submission" not in source
    assert "score_" + "clean_pair_core_v09" not in source
