import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

import audit_clean_pair_score_preflight_v09 as preflight  # noqa: E402
from clean_pair_bundle_v09 import build_clean_pair_bundle_v09  # noqa: E402


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
EVIDENCE_KEYS = (
    "input_seal_sha256",
    "input_external_audit_sha256",
    "trusted_target_source_audit_sha256",
    "legacy_reference_bridge_audit_sha256",
    "strict_nesting_seal_sha256",
    "strict_nesting_external_audit_sha256",
    "training_seal_sha256",
    "training_external_audit_sha256",
    "state_diagnostics_preregistration_sha256",
    "state_diagnostics_external_audit_sha256",
    "prediction_external_audit_sha256",
    "source_bundle_manifest_sha256",
    "environment_sha256",
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")


def _case(tmp_path: Path) -> dict:
    formal_root = tmp_path / "formal_v09"
    prediction_root = formal_root / "predictions"
    basins = ("00000001", "00000002", "00000003")
    dates = ("2000-01-01", "2000-01-02", "2000-01-03")
    trusted_root = tmp_path / "trusted"
    trusted_root.mkdir()
    basin_path = trusted_root / "basins.txt"
    basin_path.write_text("".join(f"{basin}\n" for basin in basins), encoding="utf-8")
    answer_path = trusted_root / "answer.bin"
    answer_path.write_bytes(b"synthetic-held-target-bytes")
    legacy_holdout = trusted_root / "old_holdout.txt"
    legacy_holdout.write_text("00000001\n", encoding="utf-8")
    legacy_baseline = trusted_root / "old_baseline.csv"
    legacy_baseline.write_text("basin,NSE\n00000001,0.1\n", encoding="utf-8")

    selection_paths = {}
    selection_hashes = {}
    for key in ("candidate_config", "analysis_manifest", "summary", "independent_audit"):
        path = tmp_path / "selection" / f"{key}.json"
        _write_json(path, {"status": "complete_multiseed_go", "name": key})
        selection_paths[key] = str(path)
        selection_hashes[f"{key}_sha256"] = _sha256(path)

    contract = {
        "contract_id": "S09C-CLEAN-PAIR",
        "track_id": "track0_forcing_only_clean_v09",
        "protocol_id": "P09-FORMAL",
        "protocol_sha256": "b" * 64,
        "roles": ROLES,
        "ensemble_paths": PATHS,
        "prediction_contract": {
            "basin_count": 3,
            "start_date": dates[0],
            "end_date": dates[-1],
            "dates_per_basin": 3,
            "rows_per_file": 9,
            "columns": ["basin", "date", "qsim"],
            "seeds": list(range(100, 801, 100)),
            "ensemble_operation": "float64_arithmetic_mean",
        },
        "trusted_frozen_inputs": {
            "answer_key": {"relative_path": answer_path.name, "sha256": _sha256(answer_path)},
            "basins": {"relative_path": basin_path.name, "sha256": _sha256(basin_path)},
        },
        "postseal_holdout": {
            "method": "postseal_nonce_sha256_rank_v1",
            "holdout_count": 1,
            "public_count": 2,
        },
        "legacy_nonqualifying_inputs": {
            "secret_holdout": {
                "relative_path": legacy_holdout.name,
                "sha256": _sha256(legacy_holdout),
                "status": "legacy_reused_holdout_nonqualifying",
                "qualifying": False,
                "minimum_recorded_score_calls": 7,
            },
            "historical_baseline": {
                "relative_path": legacy_baseline.name,
                "sha256": _sha256(legacy_baseline),
                "status": "historical_reference_nonqualifying",
                "qualifying": False,
            },
        },
        "selection_provenance": {
            "status": "complete_multiseed_go",
            "scope": "fixed_60_basin_internal_confirmation_only",
            **selection_hashes,
            "formal_observations_used": False,
            "may_reselect": False,
        },
    }
    contract_path = tmp_path / "contract.json"
    _write_json(contract_path, contract)

    frame = pd.DataFrame({
        "basin": [basin for basin in basins for _ in dates],
        "date": list(dates) * len(basins),
        "qsim": np.arange(9, dtype=np.float64),
    })
    predictions = {}
    for role, relative_path in PATHS.items():
        path = formal_root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        frame.to_csv(path, index=False)
        predictions[role] = {
            "experiment_id": ROLES[role],
            "relative_path": relative_path,
            "sha256": _sha256(path),
            "row_count": 9,
            "basin_count": 3,
            "dates_per_basin": 3,
            "status": "complete_prediction",
        }

    artifacts = {}
    evidence = {}
    for key in EVIDENCE_KEYS:
        path = tmp_path / "evidence" / f"{key}.json"
        _write_json(path, {"status": "complete", "name": key})
        digest = _sha256(path)
        artifacts[key] = {
            "path": str(path),
            "sha256": digest,
            "required_status": "complete",
        }
        evidence[key] = digest

    checkpoints = []
    for role, experiment_id in ROLES.items():
        for seed in range(100, 801, 100):
            path = tmp_path / "checkpoints" / f"{role}_{seed}.pt"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f"{role}-{seed}".encode())
            checkpoints.append({
                "role": role,
                "experiment_id": experiment_id,
                "seed": seed,
                "epoch": 30,
                "path": str(path),
                "sha256": _sha256(path),
            })

    source_bundle = prediction_root / "source_bundle"
    source_bundle.mkdir(parents=True)
    (source_bundle / "model.py").write_text("def predict(x):\n    return x\n", encoding="utf-8")
    source_tree = preflight.hash_tree_v09(source_bundle)
    seal = {
        "status": "complete_prediction_seal",
        "protocol_sha256": "b" * 64,
        "official_score_called": False,
        "coverage": {
            "basin_ids": list(basins),
            "start_date": dates[0],
            "end_date": dates[-1],
        },
        "predictions": predictions,
        "upstream_evidence": evidence,
        "upstream_artifacts": artifacts,
        "selection_artifacts": {
            key: {"path": path, "sha256": selection_hashes[f"{key}_sha256"]}
            for key, path in selection_paths.items()
        },
        "final_checkpoints": checkpoints,
        "source_bundle": {
            "status": "complete_source_bundle",
            "scan_hits": 0,
            "tree_sha256": source_tree["tree_sha256"],
        },
    }
    seal_path = prediction_root / "seal.json"
    _write_json(seal_path, seal)
    bundle = build_clean_pair_bundle_v09(contract, seal, formal_root)
    bundle_path = prediction_root / "clean_pair_bundle.json"
    _write_json(bundle_path, bundle)
    return {
        "contract": contract,
        "contract_path": contract_path,
        "bundle_path": bundle_path,
        "seal_path": seal_path,
        "source_bundle": source_bundle,
        "trusted_root": trusted_root,
        "ledger": tmp_path / "ledger.csv",
    }


def _audit(case: dict, **kwargs) -> dict:
    return preflight.audit_clean_pair_score_preflight_v09(
        case["contract_path"],
        case["bundle_path"],
        case["seal_path"],
        case["source_bundle"],
        case["ledger"],
        case["trusted_root"],
        available_memory_bytes=20 * 2**30,
        require_clean_worktree=False,
        **kwargs,
    )


def test_preflight_recomputes_all_nonobservational_bindings(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(
        preflight,
        "load_clean_pair_contract_v09",
        lambda *_args, **_kwargs: case["contract"],
    )
    report = _audit(case)
    assert report["status"] == "ready_for_clean_pair_score_authorization"
    assert report["answer_content_parsed"] is False
    assert report["official_score_called"] is False
    assert report["prediction_files_verified"] == 3
    assert report["checkpoint_files_verified"] == 24
    assert report["upstream_artifacts_verified"] == len(EVIDENCE_KEYS)
    assert report["selection_artifacts_verified"] == 4
    assert report["candidate_source_scan_hits"] == 0
    assert report["ledger"]["chain_breaks"] == 0
    assert report["ledger"]["experiment_id_count"] == 0
    assert report["score_approval_text"].startswith(
        "批准版本09清洁同信息配对正式评分；仅授权评分包SHA-256="
    )


@pytest.mark.parametrize("failure", ("bundle", "checkpoint", "low_memory", "existing_consumption"))
def test_preflight_failure_is_not_ready(tmp_path, monkeypatch, failure):
    case = _case(tmp_path)
    monkeypatch.setattr(
        preflight,
        "load_clean_pair_contract_v09",
        lambda *_args, **_kwargs: case["contract"],
    )
    kwargs = {}
    if failure == "bundle":
        payload = json.loads(case["bundle_path"].read_text(encoding="utf-8"))
        payload["predictions"]["baseline"]["sha256"] = "f" * 64
        _write_json(case["bundle_path"], payload)
    elif failure == "checkpoint":
        payload = json.loads(case["seal_path"].read_text(encoding="utf-8"))
        Path(payload["final_checkpoints"][0]["path"]).write_bytes(b"changed")
    elif failure == "low_memory":
        kwargs["available_memory_bytes"] = 2**30
    else:
        (case["bundle_path"].parents[1] / "clean_pair_scoring_authorization_consumed.json").write_text(
            "{}",
            encoding="utf-8",
        )
    if "available_memory_bytes" in kwargs:
        report = preflight.audit_clean_pair_score_preflight_v09(
            case["contract_path"],
            case["bundle_path"],
            case["seal_path"],
            case["source_bundle"],
            case["ledger"],
            case["trusted_root"],
            require_clean_worktree=False,
            **kwargs,
        )
    else:
        report = _audit(case)
    assert report["status"] == "not_ready_for_clean_pair_score_authorization"
    assert report["errors"]


def test_preflight_module_has_no_answer_loader_or_score_call():
    source = (IDEA_ROOT / "audit_clean_pair_score_preflight_v09.py").read_text(encoding="utf-8")
    assert "load_" + "obs_csv" not in source
    assert "score_" + "submission(" not in source
