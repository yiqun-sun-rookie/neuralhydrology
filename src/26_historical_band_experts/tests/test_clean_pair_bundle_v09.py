import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

from clean_pair_bundle_v09 import (  # noqa: E402
    CleanPairBundleError,
    build_clean_pair_bundle_v09,
    clean_pair_bundle_sha256,
)


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
BASINS = ("00000001", "00000002", "00000003")
DATES = ("2000-01-01", "2000-01-02", "2000-01-03")
HASH64 = "a" * 64
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


def _contract() -> dict:
    return {
        "contract_id": "S09C-CLEAN-PAIR",
        "track_id": "track0_forcing_only_clean_v09",
        "protocol_id": "P09-FORMAL",
        "protocol_sha256": "b" * 64,
        "roles": ROLES,
        "ensemble_paths": PATHS,
        "prediction_contract": {
            "basin_count": len(BASINS),
            "start_date": DATES[0],
            "end_date": DATES[-1],
            "dates_per_basin": len(DATES),
            "rows_per_file": len(BASINS) * len(DATES),
            "columns": ["basin", "date", "qsim"],
            "seeds": list(range(100, 801, 100)),
            "ensemble_operation": "float64_arithmetic_mean",
        },
        "postseal_holdout": {
            "method": "postseal_nonce_sha256_rank_v1",
            "holdout_count": 1,
            "public_count": 2,
        },
    }


def _frame(offset: float = 0.0) -> pd.DataFrame:
    return pd.DataFrame({
        "basin": [basin for basin in BASINS for _ in DATES],
        "date": list(DATES) * len(BASINS),
        "qsim": np.arange(len(BASINS) * len(DATES), dtype=np.float64) + offset,
    })


def _checkpoints() -> list[dict]:
    records = []
    for role, experiment_id in ROLES.items():
        for seed in range(100, 801, 100):
            records.append({
                "role": role,
                "experiment_id": experiment_id,
                "seed": seed,
                "epoch": 30,
                "sha256": hashlib.sha256(f"{role}-{seed}".encode()).hexdigest(),
            })
    return records


def write_three_synthetic_ensembles(tmp_path: Path) -> tuple[Path, dict]:
    root = tmp_path / "formal_v09"
    predictions = {}
    for index, (role, relative_path) in enumerate(PATHS.items()):
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        _frame(float(index)).to_csv(path, index=False)
        predictions[role] = {
            "experiment_id": ROLES[role],
            "relative_path": relative_path,
            "sha256": _sha256(path),
            "row_count": len(BASINS) * len(DATES),
            "basin_count": len(BASINS),
            "dates_per_basin": len(DATES),
            "status": "complete_prediction",
        }
    seal = {
        "status": "complete_prediction_seal",
        "protocol_sha256": "b" * 64,
        "official_score_called": False,
        "coverage": {
            "basin_ids": list(BASINS),
            "start_date": DATES[0],
            "end_date": DATES[-1],
        },
        "predictions": predictions,
        "upstream_evidence": {key: HASH64 for key in EVIDENCE_KEYS},
        "final_checkpoints": _checkpoints(),
        "source_bundle": {
            "status": "complete_source_bundle",
            "scan_hits": 0,
            "tree_sha256": "c" * 64,
        },
    }
    return root, seal


def test_clean_pair_bundle_assigns_three_fixed_roles(tmp_path):
    root, seal = write_three_synthetic_ensembles(tmp_path)
    bundle = build_clean_pair_bundle_v09(_contract(), seal, root)
    assert tuple(bundle["predictions"]) == (
        "baseline",
        "capacity_control",
        "challenger",
    )
    assert bundle["predictions"]["baseline"]["experiment_id"] == "B09-CLASSIC"
    assert bundle["predictions"]["challenger"]["experiment_id"] == "E09-CONTINUOUS"
    assert bundle["postseal_holdout"] == {
        "method": "postseal_nonce_sha256_rank_v1",
        "status": "awaiting_authorized_nonce_draw",
        "holdout_count": 1,
        "public_count": 2,
    }
    assert "nonce_hex" not in json.dumps(bundle)
    assert "holdout_set_sha256" not in json.dumps(bundle)
    assert bundle["status"] == "complete_clean_pair_bundle"
    assert bundle["bundle_sha256"] == clean_pair_bundle_sha256(bundle)
    assert len(bundle["final_checkpoints"]) == 24


@pytest.mark.parametrize("failure", ("duplicate", "missing", "nonfinite", "extra_column"))
def test_clean_pair_bundle_rejects_malformed_rows(tmp_path, failure):
    root, seal = write_three_synthetic_ensembles(tmp_path)
    path = root / PATHS["challenger"]
    frame = pd.read_csv(path, dtype={"basin": str})
    if failure == "duplicate":
        frame.iloc[-1] = frame.iloc[0]
    elif failure == "missing":
        frame = frame.iloc[:-1]
    elif failure == "nonfinite":
        frame.loc[0, "qsim"] = np.inf
    else:
        frame["extra"] = 1
    frame.to_csv(path, index=False)
    seal["predictions"]["challenger"]["sha256"] = _sha256(path)
    seal["predictions"]["challenger"]["row_count"] = len(frame)
    with pytest.raises(CleanPairBundleError):
        build_clean_pair_bundle_v09(_contract(), seal, root)


@pytest.mark.parametrize(
    "mutation",
    ("prediction_hash", "experiment_role", "missing_evidence", "checkpoint_epoch", "score_called"),
)
def test_clean_pair_bundle_rejects_seal_drift(tmp_path, mutation):
    root, seal = write_three_synthetic_ensembles(tmp_path)
    if mutation == "prediction_hash":
        seal["predictions"]["baseline"]["sha256"] = "f" * 64
    elif mutation == "experiment_role":
        seal["predictions"]["baseline"]["experiment_id"] = "E09-CONTINUOUS"
    elif mutation == "missing_evidence":
        seal["upstream_evidence"].pop("strict_nesting_external_audit_sha256")
    elif mutation == "checkpoint_epoch":
        seal["final_checkpoints"][0]["epoch"] = 20
    else:
        seal["official_score_called"] = True
    with pytest.raises(CleanPairBundleError):
        build_clean_pair_bundle_v09(_contract(), seal, root)


def test_clean_pair_bundle_module_contains_no_forbidden_reader_tokens():
    source = (IDEA_ROOT / "clean_pair_bundle_v09.py").read_text(encoding="utf-8").lower()
    tokens = (
        "usgs_" + "streamflow",
        "camels_" + "hydro",
        "load_" + "obs_csv",
        "_obs_" + "eval.parquet",
    )
    assert [token for token in tokens if token in source] == []
