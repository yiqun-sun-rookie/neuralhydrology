from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from audit_comparability_v06 import (
    audit_candidate_v06,
    bootstrap_median_ci_v06,
    validate_comparability_audit_config_v06,
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_v06_bootstrap_median_interval_is_deterministic_and_exact_for_constant_delta():
    delta = np.full(60, 0.002, dtype=np.float64)

    first = bootstrap_median_ci_v06(delta, 1000, seed=20260727)
    second = bootstrap_median_ci_v06(delta, 1000, seed=20260727)

    assert first == second == (0.002, 0.002)


def test_v06_candidate_audit_distinguishes_superiority_from_posthoc_equivalence():
    paired = pd.DataFrame({
        "basin": [f"{index:08d}" for index in range(60)],
        "nse_classic": np.linspace(0.4, 0.8, 60),
        "nse_candidate": np.linspace(0.4, 0.8, 60) + 0.001,
    })

    result = audit_candidate_v06(
        paired,
        margin=0.01,
        bootstrap_resamples=1000,
        bootstrap_seed=20260727,
        candidate_training_seed_count=1,
    )

    assert result["superiority_delta_at_least_0_01"] is False
    assert result["posthoc_practical_equivalence_within_plus_minus_0_01"] is True
    assert result["posthoc_noninferior_to_minus_0_01"] is True
    assert result["candidate_training_seed_count"] == 1


def test_v06_real_comparability_audit_config_and_input_hashes_are_frozen():
    idea = Path(__file__).resolve().parents[1]
    repo = idea.parents[1]
    config = json.loads(
        (idea / "configs/comparability_audit_v06.json").read_text(encoding="utf-8")
    )

    validate_comparability_audit_config_v06(config)
    for item in config["inputs"]:
        assert _sha256(repo / item["paired_file"]) == item["sha256"]

