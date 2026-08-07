"""Freeze the 24-run main-training order and the paired dropout RNG streams.

The order is frozen in two independent places on purpose: this JSON file and
``stage_authorization_v09.MAIN_ALLOWED_RUNS``. They must agree exactly, so a silent edit
to either one is caught here rather than at execution time.
"""
from pathlib import Path
import copy
import json
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

ORDER_PATH = IDEA_ROOT / "configs/formal_v09_run_order.json"

# The table from the frozen plan, transcribed independently of the JSON file.
_PLANNED_TABLE = (
    (100, ("B09-CLASSIC", "B09-CAPACITY", "E09-CONTINUOUS")),
    (200, ("B09-CLASSIC", "E09-CONTINUOUS", "B09-CAPACITY")),
    (300, ("B09-CAPACITY", "B09-CLASSIC", "E09-CONTINUOUS")),
    (400, ("B09-CAPACITY", "E09-CONTINUOUS", "B09-CLASSIC")),
    (500, ("E09-CONTINUOUS", "B09-CLASSIC", "B09-CAPACITY")),
    (600, ("E09-CONTINUOUS", "B09-CAPACITY", "B09-CLASSIC")),
    (700, ("B09-CLASSIC", "B09-CAPACITY", "E09-CONTINUOUS")),
    (800, ("B09-CAPACITY", "E09-CONTINUOUS", "B09-CLASSIC")),
)


def _raw_order():
    return json.loads(ORDER_PATH.read_text(encoding="utf-8"))


def test_frozen_order_matches_the_planned_table_position_by_position():
    from train_formal_v09 import validate_run_order_v09

    specs = validate_run_order_v09(_raw_order())
    assert len(specs) == 24
    expected = [(seed, family) for seed, families in _PLANNED_TABLE for family in families]
    assert [(s.seed, s.family) for s in specs] == expected
    assert [s.position for s in specs] == list(range(1, 25))


def test_frozen_order_agrees_with_the_authorization_module():
    from stage_authorization_v09 import MAIN_ALLOWED_RUNS
    from train_formal_v09 import validate_run_order_v09

    specs = validate_run_order_v09(_raw_order())
    assert tuple(s.run_id for s in specs) == MAIN_ALLOWED_RUNS


def test_each_family_has_eight_runs_and_each_seed_has_three():
    from train_formal_v09 import validate_run_order_v09

    specs = validate_run_order_v09(_raw_order())
    families = {}
    seeds = {}
    for s in specs:
        families[s.family] = families.get(s.family, 0) + 1
        seeds[s.seed] = seeds.get(s.seed, 0) + 1
    assert families == {"B09-CLASSIC": 8, "B09-CAPACITY": 8, "E09-CONTINUOUS": 8}
    assert seeds == {seed: 3 for seed, _ in _PLANNED_TABLE}
    assert len({s.run_id for s in specs}) == 24


def test_parameter_counts_and_variants_match_the_model_registry():
    from models_formal_v09 import _EXPECTED_TRAINABLE_COUNTS
    from train_formal_v09 import validate_run_order_v09

    specs = validate_run_order_v09(_raw_order())
    for s in specs:
        assert _EXPECTED_TRAINABLE_COUNTS[s.variant] == s.trainable_parameters


def test_each_family_has_its_own_results_root():
    from train_formal_v09 import validate_run_order_v09

    specs = validate_run_order_v09(_raw_order())
    roots = {s.family: s.results_root for s in specs}
    assert roots == {
        "B09-CLASSIC": "results/26_historical_band_experts/formal_v09/classic",
        "B09-CAPACITY": "results/26_historical_band_experts/formal_v09/capacity",
        "E09-CONTINUOUS": "results/26_historical_band_experts/formal_v09/continuous",
    }
    assert len(set(roots.values())) == 3


def _mutate(fn):
    order = _raw_order()
    fn(order)
    return order


@pytest.mark.parametrize(
    "mutate, match",
    [
        # swapping two adjacent runs must fail even though counts stay correct
        (lambda o: o["runs"].insert(0, o["runs"].pop(1)), "position"),
        # dropping a run
        (lambda o: o["runs"].pop(5), "24"),
        # duplicating a run id
        (lambda o: o["runs"].__setitem__(7, {**o["runs"][7], "run_id": o["runs"][6]["run_id"]}), "run identifier"),
        # renaming a family to one that is not registered
        (lambda o: o["runs"].__setitem__(0, {**o["runs"][0], "family": "B09-GHOST"}), "family"),
        # a seed that is not in the frozen seed list
        (lambda o: o["runs"].__setitem__(0, {**o["runs"][0], "seed": 999}), "seed"),
        # run_id that disagrees with its own family/seed
        (lambda o: o["runs"].__setitem__(0, {**o["runs"][0], "run_id": "B09-CLASSIC-S200"}), "run identifier"),
        # renumbering positions
        (lambda o: o["runs"].__setitem__(3, {**o["runs"][3], "position": 99}), "position"),
        # two families sharing one results root
        (lambda o: o["families"]["B09-CAPACITY"].__setitem__(
            "results_root", o["families"]["B09-CLASSIC"]["results_root"]), "results root"),
        # a parameter count that disagrees with the model registry
        (lambda o: o["families"]["B09-CLASSIC"].__setitem__("trainable_parameters", 297218), "parameter"),
        # wrong schema
        (lambda o: o.__setitem__("schema", "something_else"), "schema"),
        # wrong scope
        (lambda o: o.__setitem__("scope", "FORMAL-MAIN-12"), "scope"),
    ],
)
def test_validator_rejects_every_drift(mutate, match):
    from train_formal_v09 import validate_run_order_v09

    with pytest.raises(ValueError, match=match):
        validate_run_order_v09(_mutate(mutate))


def test_loader_reads_the_frozen_file_from_disk():
    from train_formal_v09 import load_run_order_v09, validate_run_order_v09

    assert load_run_order_v09(ORDER_PATH) == validate_run_order_v09(_raw_order())


def test_run_order_file_is_not_mutated_by_validation():
    from train_formal_v09 import validate_run_order_v09

    order = _raw_order()
    before = copy.deepcopy(order)
    validate_run_order_v09(order)
    assert order == before


# --------------------------------------------------------------------------------------
# dropout RNG streams
# --------------------------------------------------------------------------------------


def test_dropout_seed_is_deterministic_and_separate_from_the_model_seed():
    from train_formal_v09 import dropout_seed_v09

    assert dropout_seed_v09(100) == dropout_seed_v09(100)
    assert dropout_seed_v09(100) != 100
    assert len({dropout_seed_v09(s) for s, _ in _PLANNED_TABLE}) == 8


def test_dropout_seed_matches_the_strict_stage_formula():
    """The strict stage already burned this stream in; the main runs must not diverge."""
    from train_formal_v09 import dropout_seed_v09

    assert dropout_seed_v09(100) == 100 * 1_000_003 + 900_001


def test_reset_dropout_rng_is_reproducible_and_reports_state_hashes():
    from train_formal_v09 import reset_training_dropout_rng_v09

    first = reset_training_dropout_rng_v09(100)
    second = reset_training_dropout_rng_v09(100)
    assert first == second
    assert first["dropout_seed"] == 100 * 1_000_003 + 900_001
    assert len(first["cpu_state_sha256"]) == 64
    other = reset_training_dropout_rng_v09(200)
    assert other["cpu_state_sha256"] != first["cpu_state_sha256"]


def test_all_three_families_of_one_seed_share_the_same_dropout_stream():
    """Required so the classic and continuous recent-path dropout stays paired."""
    from train_formal_v09 import dropout_seed_v09, load_run_order_v09

    specs = load_run_order_v09(ORDER_PATH)
    by_seed = {}
    for s in specs:
        by_seed.setdefault(s.seed, set()).add(dropout_seed_v09(s.seed))
    assert all(len(v) == 1 for v in by_seed.values())
