import json
import hashlib
from datetime import datetime
from pathlib import Path

import pytest


MODULE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = MODULE_ROOT.parents[1]
FROZEN_STATIC_TABLE = REPO_ROOT / "src" / "fair_benchmark" / "frozen" / "bundle" / "track0_statics.csv"
ELIGIBLE_BASIN_LIST = REPO_ROOT / "examples" / "06-Finetuning" / "531_basin_list.txt"
HISTORICAL_SELECTION_PATH = MODULE_ROOT / "selection" / "development_basins_64_v1.json"
CONFIRMATION_SELECTION_PATH = MODULE_ROOT / "selection" / "development_basins_confirmation_64_v1.json"
REGISTRY_PATH = MODULE_ROOT / "evidence" / "PROSPECTIVE_CONFIRMATION_REGISTRY_20260811.json"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_confirmation_block_is_exactly_ranks_65_through_128_and_disjoint():
    from unified_autoresearch.selection.basins import (
        select_development_basin_block,
        select_development_basins,
    )

    historical = json.loads(HISTORICAL_SELECTION_PATH.read_text(encoding="utf-8"))["basins"]
    ranked = select_development_basins(FROZEN_STATIC_TABLE, ELIGIBLE_BASIN_LIST, count=128)
    confirmation = select_development_basin_block(
        FROZEN_STATIC_TABLE,
        ELIGIBLE_BASIN_LIST,
        rank_start=65,
        count=64,
    )

    assert ranked[:64] == historical
    assert confirmation == ranked[64:128]
    assert len(confirmation) == len(set(confirmation)) == 64
    assert set(confirmation).isdisjoint(historical)


@pytest.mark.parametrize(
    ("rank_start", "count"),
    [(True, 64), (65, False), (0, 64), (65, 0), (500, 64)],
)
def test_confirmation_block_rejects_invalid_rank_ranges(rank_start, count):
    from unified_autoresearch.selection.basins import select_development_basin_block

    with pytest.raises(ValueError, match="rank range"):
        select_development_basin_block(
            FROZEN_STATIC_TABLE,
            ELIGIBLE_BASIN_LIST,
            rank_start=rank_start,
            count=count,
        )


def test_confirmation_block_freeze_is_exclusive_and_records_provenance(tmp_path):
    from unified_autoresearch.selection.basins import freeze_selection_block

    output_path = tmp_path / "confirmation.json"
    value = freeze_selection_block(
        FROZEN_STATIC_TABLE,
        ELIGIBLE_BASIN_LIST,
        HISTORICAL_SELECTION_PATH,
        output_path,
        rank_start=65,
        count=64,
    )

    assert json.loads(output_path.read_text(encoding="utf-8")) == value
    assert value["selection_method"] == "deterministic_standardized_farthest_point_block_v1"
    assert value["selection_inputs"] == "static attributes only; no discharge or model results"
    assert value["selection_rank_range"] == [65, 128]
    assert value["historical_selection_sha256"] == (
        "3d75df6cfce527b8f6580a9dcfe0eacccb65c8bd7aae987ce23ead462ab00e53"
    )
    assert len(value["basins"]) == 64
    with pytest.raises(FileExistsError):
        freeze_selection_block(
            FROZEN_STATIC_TABLE,
            ELIGIBLE_BASIN_LIST,
            HISTORICAL_SELECTION_PATH,
            output_path,
            rank_start=65,
            count=64,
        )


def test_development_builders_accept_only_the_exact_confirmation_record(tmp_path):
    from unified_autoresearch.data.packages import load_frozen_selection

    frozen = json.loads(CONFIRMATION_SELECTION_PATH.read_text(encoding="utf-8"))
    assert load_frozen_selection(CONFIRMATION_SELECTION_PATH) == frozen

    drifted = dict(frozen)
    drifted["basins"] = list(reversed(frozen["basins"]))
    drifted_path = tmp_path / "drifted.json"
    drifted_path.write_text(json.dumps(drifted), encoding="utf-8")
    with pytest.raises(ValueError, match="frozen development basin selection mismatch"):
        load_frozen_selection(drifted_path)


def test_prospective_registry_freezes_one_candidate_before_any_confirmation_result():
    from unified_autoresearch.selection.basins import select_development_basin_block

    registry = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    historical = json.loads(HISTORICAL_SELECTION_PATH.read_text(encoding="utf-8"))["basins"]
    confirmation = json.loads(CONFIRMATION_SELECTION_PATH.read_text(encoding="utf-8"))["basins"]
    recomputed = select_development_basin_block(
        FROZEN_STATIC_TABLE,
        ELIGIBLE_BASIN_LIST,
        rank_start=65,
        count=64,
    )

    frozen_at = datetime.fromisoformat(registry["frozen_at"])
    assert frozen_at.tzinfo is not None and frozen_at.utcoffset() is not None
    assert registry["schema_version"] == "prospective_confirmation_registry_v1"
    assert registry["candidate"] == {
        "candidate_id": "hbv-lite-calibrated-v1",
        "category": "conceptual_rainfall_runoff",
        "seed": 29,
    }
    assert registry["changed_factor"] == "basin_set"
    assert registry["candidate_count"] == 1
    assert registry["confirmation_result_available_at_freeze"] is False
    assert registry["historical_equivalent_result_known"] is True
    assert registry["selection"]["sha256"] == _sha256(CONFIRMATION_SELECTION_PATH)
    assert registry["selection"]["rank_range"] == [65, 128]
    assert registry["selection"]["historical_overlap_count"] == 0
    assert confirmation == recomputed
    assert set(confirmation).isdisjoint(historical)
    assert registry["protected_boundaries"] == {
        "sealed_final_evaluation_read_or_scored": False,
        "fair_benchmark_scoring_program_run": False,
        "formal_basin_search_run": False,
        "baseline_outperformance_claimed": False,
    }
