import copy
import hashlib
import json
from pathlib import Path

import pytest

from fair_benchmark.clean_pair_authorization_v09 import (
    CleanPairAuthorizationError,
    clean_pair_ledger_snapshot_v09,
    consume_clean_pair_score_authorization_v09,
    draw_holdout_nonce_once_v09,
    render_clean_pair_score_approval_text,
    trusted_module_import_probe_v09,
    trusted_source_tree_v09,
    validate_clean_pair_score_authorization_v09,
)


HASHES = {
    "baseline": "a" * 64,
    "capacity_control": "b" * 64,
    "challenger": "c" * 64,
}
BUNDLE_SHA = "d" * 64
CONTRACT_SHA = "e" * 64
BASINS = [f"{index:08d}" for index in range(531)]
SOURCE_TREE = {
    "git_head": "f" * 40,
    "tree_sha256": "f" * 64,
    "files": {
        "src/fair_benchmark/score_clean_pair_v09.py": "1" * 64,
        "src/fair_benchmark/clean_pair_authorization_v09.py": "2" * 64,
    },
}
LEDGER_SNAPSHOT = {
    "row_count": 7,
    "sha256": "3" * 64,
    "last_row_hash": "4" * 64,
    "experiment_id_count": 0,
    "chain_breaks": 0,
}
CONTRACT = {
    "contract_id": "S09C-CLEAN-PAIR",
    "track_id": "track0_forcing_only_clean_v09",
    "protocol_sha256": "5" * 64,
    "trusted_frozen_inputs": {
        "answer_key": {"relative_path": "answer.parquet", "sha256": "6" * 64},
        "basins": {"relative_path": "basins.txt", "sha256": "7" * 64},
    },
    "postseal_holdout": {
        "method": "postseal_nonce_sha256_rank_v1",
        "nonce_source": "python_secrets_token_bytes_32_after_authorization_consumption",
        "nonce_draws": 1,
        "nonce_redraws": 0,
        "holdout_count": 107,
        "public_count": 424,
    },
    "legacy_nonqualifying_inputs": {
        "secret_holdout": {
            "sha256": "8" * 64,
            "status": "legacy_reused_holdout_nonqualifying",
            "qualifying": False,
        },
        "historical_baseline": {
            "sha256": "9" * 64,
            "status": "historical_reference_nonqualifying",
            "qualifying": False,
        },
    },
    "selection_provenance": {
        "candidate_config_sha256": "a" * 64,
        "analysis_manifest_sha256": "b" * 64,
        "summary_sha256": "c" * 64,
        "independent_audit_sha256": "d" * 64,
        "status": "complete_multiseed_go",
        "may_reselect": False,
    },
}
BUNDLE = {
    "bundle_sha256": BUNDLE_SHA,
    "contract_sha256": CONTRACT_SHA,
    "prediction_seal_sha256": "e" * 64,
    "predictions": {
        role: {
            "experiment_id": experiment_id,
            "relative_path": f"predictions/{role}.csv",
            "sha256": HASHES[role],
        }
        for role, experiment_id in (
            ("baseline", "B09-CLASSIC"),
            ("capacity_control", "B09-CAPACITY"),
            ("challenger", "E09-CONTINUOUS"),
        )
    },
    "upstream_evidence": {
        "input_seal_sha256": "1" * 64,
        "strict_nesting_seal_sha256": "2" * 64,
        "strict_nesting_external_audit_sha256": "3" * 64,
        "training_seal_sha256": "4" * 64,
        "training_external_audit_sha256": "5" * 64,
        "prediction_external_audit_sha256": "6" * 64,
    },
    "final_checkpoints": [
        {
            "role": role,
            "seed": seed,
            "epoch": 30,
            "sha256": hashlib.sha256(f"{role}-{seed}".encode()).hexdigest(),
        }
        for role in HASHES
        for seed in range(100, 801, 100)
    ],
    "postseal_holdout": {
        "method": "postseal_nonce_sha256_rank_v1",
        "status": "awaiting_authorized_nonce_draw",
        "holdout_count": 107,
        "public_count": 424,
    },
}
RUNTIME = {
    "python_executable": "C:/Python311/python.exe",
    "worktree_src": "G:/repo/worktree/src",
    "pythonpath": "G:/repo/worktree/src",
}


def _receipt() -> dict:
    approval_text = render_clean_pair_score_approval_text(BUNDLE_SHA)
    return {
        "status": "authorized_clean_pair_score",
        "approval": {
            "text": approval_text,
            "utf8_sha256": hashlib.sha256(approval_text.encode("utf-8")).hexdigest(),
            "task_id": "synthetic-task",
            "approved_at": "2026-07-31T00:00:00+08:00",
        },
        "contract_sha256": CONTRACT_SHA,
        "bundle_sha256": BUNDLE_SHA,
        "prediction_sha256": HASHES,
        "prediction_seal_sha256": BUNDLE["prediction_seal_sha256"],
        "upstream_evidence": BUNDLE["upstream_evidence"],
        "selection_provenance": CONTRACT["selection_provenance"],
        "final_checkpoints": BUNDLE["final_checkpoints"],
        "source_tree": SOURCE_TREE,
        "runtime": RUNTIME,
        "trusted_frozen_inputs": CONTRACT["trusted_frozen_inputs"],
        "trusted_frozen_root": "G:/trusted/frozen",
        "postseal_holdout": {
            "method": "postseal_nonce_sha256_rank_v1",
            "nonce_source": "python_secrets_token_bytes_32_after_authorization_consumption",
            "nonce_draws": 1,
            "nonce_redraws": 0,
            "holdout_count": 107,
            "public_count": 424,
        },
        "legacy_nonqualifying_inputs": CONTRACT["legacy_nonqualifying_inputs"],
        "ledger_snapshot": LEDGER_SNAPSHOT,
        "allowed_experiment_id": "S09C-CLEAN-PAIR",
        "allowed_track_id": "track0_forcing_only_clean_v09",
        "output_root": "results/26_historical_band_experts/formal_v09/clean_pair_score_attempt_01",
        "maximum_attempts": 1,
    }


def test_clean_pair_authorization_binds_all_predictions_runtime_and_ledger():
    receipt = _receipt()
    validated = validate_clean_pair_score_authorization_v09(
        receipt,
        contract=CONTRACT,
        bundle=BUNDLE,
        source_tree=SOURCE_TREE,
        ledger_snapshot=LEDGER_SNAPSHOT,
    )
    assert validated["maximum_attempts"] == 1
    assert validated["allowed_experiment_id"] == "S09C-CLEAN-PAIR"
    assert validated["prediction_sha256"] == HASHES
    assert validated["postseal_holdout"] == {
        "method": "postseal_nonce_sha256_rank_v1",
        "nonce_source": "python_secrets_token_bytes_32_after_authorization_consumption",
        "nonce_draws": 1,
        "nonce_redraws": 0,
        "holdout_count": 107,
        "public_count": 424,
    }
    assert validated["runtime"]["pythonpath"] == validated["runtime"]["worktree_src"]


@pytest.mark.parametrize(
    "field",
    ("bundle_sha256", "prediction_sha256", "source_tree", "ledger_snapshot", "runtime"),
)
def test_clean_pair_authorization_rejects_binding_drift(field):
    receipt = _receipt()
    if field == "prediction_sha256":
        receipt[field] = dict(HASHES, challenger="f" * 64)
    elif field == "runtime":
        receipt[field] = dict(RUNTIME, pythonpath="G:/other/src")
    elif field in ("source_tree", "ledger_snapshot"):
        receipt[field] = {}
    else:
        receipt[field] = "f" * 64
    with pytest.raises(CleanPairAuthorizationError):
        validate_clean_pair_score_authorization_v09(
            receipt,
            contract=CONTRACT,
            bundle=BUNDLE,
            source_tree=SOURCE_TREE,
            ledger_snapshot=LEDGER_SNAPSHOT,
        )


def test_clean_pair_authorization_consumes_exclusively_once(tmp_path):
    path = tmp_path / "consumed.json"
    first = consume_clean_pair_score_authorization_v09(
        _receipt(),
        path,
        {
            "timestamp": "2026-07-31T00:01:00+08:00",
            "task_id": "independent-score-task",
            "runtime": RUNTIME,
        },
    )
    assert first["status"] == "consumed_no_retry"
    with pytest.raises(CleanPairAuthorizationError, match="already exists"):
        consume_clean_pair_score_authorization_v09(_receipt(), path, {})


def test_authorization_helpers_bind_trusted_service_tree_and_empty_ledger(tmp_path):
    worktree_src = Path(__file__).resolve().parents[2]
    tree = trusted_source_tree_v09(worktree_src)
    assert len(tree["files"]) == 13
    assert "fair_benchmark/score_clean_pair_v09.py" in tree["files"]
    assert "fair_benchmark/task_memory_v09.py" in tree["files"]
    assert len(tree["git_head"]) == 40
    assert len(tree["tree_sha256"]) == 64
    probe = trusted_module_import_probe_v09(worktree_src, verify_live_process=True)
    assert probe["clean_subprocess"] == probe["live_process"]
    assert len(probe["paths_sha256"]) == 64

    snapshot = clean_pair_ledger_snapshot_v09(tmp_path / "missing.csv")
    assert snapshot == {
        "row_count": 0,
        "sha256": hashlib.sha256(b"").hexdigest(),
        "last_row_hash": "GENESIS",
        "experiment_id_count": 0,
        "chain_breaks": 0,
    }


def test_holdout_nonce_is_drawn_once_only_after_consumption(tmp_path):
    consumption = tmp_path / "consumed.json"
    draw = tmp_path / "holdout_draw.json"
    with pytest.raises(CleanPairAuthorizationError, match="consumption"):
        draw_holdout_nonce_once_v09(
            consumption,
            draw,
            contract=CONTRACT,
            bundle=BUNDLE,
            basin_ids=BASINS,
        )

    consume_clean_pair_score_authorization_v09(
        _receipt(),
        consumption,
        {"timestamp": "2026-07-31T00:01:00+08:00", "runtime": RUNTIME},
    )
    calls = {"count": 0}

    def fixed_random_bytes(length):
        calls["count"] += 1
        assert length == 32
        return b"\x01" * length

    receipt = draw_holdout_nonce_once_v09(
        consumption,
        draw,
        contract=CONTRACT,
        bundle=BUNDLE,
        basin_ids=BASINS,
        random_bytes=fixed_random_bytes,
    )
    assert calls["count"] == 1
    assert receipt["nonce_hex"] == "01" * 32
    assert receipt["prediction_sha256"] == HASHES
    json.dumps(receipt, allow_nan=False)
    with pytest.raises(CleanPairAuthorizationError, match="already exists"):
        draw_holdout_nonce_once_v09(
            consumption,
            draw,
            contract=CONTRACT,
            bundle=BUNDLE,
            basin_ids=BASINS,
            random_bytes=fixed_random_bytes,
        )
    assert calls["count"] == 1


def test_failed_random_draw_still_burns_the_attempt(tmp_path):
    consumption = tmp_path / "consumed.json"
    draw = tmp_path / "holdout_draw.json"
    consume_clean_pair_score_authorization_v09(
        _receipt(),
        consumption,
        {"timestamp": "2026-07-31T00:01:00+08:00", "runtime": RUNTIME},
    )
    with pytest.raises(CleanPairAuthorizationError, match="32 bytes"):
        draw_holdout_nonce_once_v09(
            consumption,
            draw,
            contract=CONTRACT,
            bundle=BUNDLE,
            basin_ids=BASINS,
            random_bytes=lambda _: b"short",
        )
    assert draw.exists()
    with pytest.raises(CleanPairAuthorizationError, match="already exists"):
        draw_holdout_nonce_once_v09(
            consumption,
            draw,
            contract=CONTRACT,
            bundle=BUNDLE,
            basin_ids=BASINS,
        )


def test_rendered_score_approval_is_exact_and_hash_bound():
    text = render_clean_pair_score_approval_text("a" * 64)
    assert text == (
        "批准版本09清洁同信息配对正式评分；仅授权评分包SHA-256="
        + "a" * 64
        + "在S09C-CLEAN-PAIR中消费一次授权、抽取一次256位留出随机数并调用评分一次；"
        "不批准重抽、重试或其他评分。"
    )
    with pytest.raises(CleanPairAuthorizationError):
        render_clean_pair_score_approval_text("A" * 64)
