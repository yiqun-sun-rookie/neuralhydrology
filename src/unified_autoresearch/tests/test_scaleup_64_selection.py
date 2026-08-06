"""The frozen sixty-four-basin selection must be reproducible from its declared inputs."""

import hashlib
import json
from pathlib import Path

import pytest

from unified_autoresearch.selection.basins import (
    SELECTION_METHOD,
    freeze_selection,
    select_development_basins,
)


MODULE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = MODULE_ROOT.parents[1]
FROZEN_STATIC_TABLE = MODULE_ROOT.parent / "fair_benchmark" / "frozen" / "bundle" / "track0_statics.csv"
ELIGIBLE_BASIN_LIST = REPO_ROOT / "examples" / "06-Finetuning" / "531_basin_list.txt"
FROZEN_EIGHT_PATH = MODULE_ROOT / "selection" / "development_basins_v1.json"
FROZEN_SIXTY_FOUR_PATH = MODULE_ROOT / "selection" / "development_basins_64_v1.json"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _record(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_frozen_sixty_four_record_declares_the_two_frozen_selection_inputs():
    record = _record(FROZEN_SIXTY_FOUR_PATH)

    assert record["schema_version"] == 1
    assert record["selection_method"] == SELECTION_METHOD
    assert record["selection_inputs"] == "static attributes only; no discharge or model results"
    assert record["static_sha256"] == _sha256(FROZEN_STATIC_TABLE)
    assert record["eligible_basins_sha256"] == _sha256(ELIGIBLE_BASIN_LIST)


def test_frozen_sixty_four_basins_recompute_exactly_from_the_declared_inputs():
    record = _record(FROZEN_SIXTY_FOUR_PATH)

    recomputed = select_development_basins(FROZEN_STATIC_TABLE, ELIGIBLE_BASIN_LIST, count=64)

    assert record["basins"] == recomputed
    assert len(record["basins"]) == 64
    assert len(set(record["basins"])) == 64
    assert all(len(basin) == 8 and basin.isdigit() for basin in record["basins"])


def test_frozen_sixty_four_selection_contains_the_eight_frozen_development_basins_as_its_prefix():
    """Farthest-point selection is incremental, so the sixty-four set extends the eight without drift."""
    eight = _record(FROZEN_EIGHT_PATH)
    sixty_four = _record(FROZEN_SIXTY_FOUR_PATH)

    assert sixty_four["basins"][:8] == eight["basins"]
    assert sixty_four["static_sha256"] == eight["static_sha256"]
    assert sixty_four["eligible_basins_sha256"] == eight["eligible_basins_sha256"]


def test_frozen_sixty_four_basins_are_all_drawn_from_the_eligible_five_hundred_and_thirty_one():
    eligible = {line.strip().zfill(8) for line in ELIGIBLE_BASIN_LIST.read_text(encoding="utf-8").splitlines() if line.strip()}
    record = _record(FROZEN_SIXTY_FOUR_PATH)

    assert len(eligible) == 531
    assert set(record["basins"]) <= eligible


def test_refreezing_into_a_scratch_path_reproduces_the_committed_record_byte_for_byte(tmp_path):
    """Freeze into scratch, never into the source tree, so the committed record stays untouched."""
    scratch = tmp_path / "development_basins_64_v1.json"

    freeze_selection(FROZEN_STATIC_TABLE, ELIGIBLE_BASIN_LIST, scratch, count=64)

    assert scratch.read_bytes() == FROZEN_SIXTY_FOUR_PATH.read_bytes()
    with pytest.raises(FileExistsError):
        freeze_selection(FROZEN_STATIC_TABLE, ELIGIBLE_BASIN_LIST, scratch, count=64)
