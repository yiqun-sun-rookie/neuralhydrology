"""Unit tests for the ID10 saved-parameter replay audit helper."""
import os
import sys
import unittest

import numpy as np
import pandas as pd

_HERE = os.path.dirname(__file__)
_REPO_ROOT = os.path.abspath(os.path.join(_HERE, ".."))
_SRC_ROOT = os.path.join(_REPO_ROOT, "src")
for _p in (_REPO_ROOT, _SRC_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from src.xaj_global_pilot.scripts.replay_conceptual_saved_params import (  # noqa: E402
    _classify_replay_status,
    _extract_params,
    _extract_state_dict,
    _extract_state_vector,
    summarize_replay_rows,
)


class TestSavedParameterReplayHelpers(unittest.TestCase):
    def test_extract_params_requires_all_named_p_columns(self):
        row = pd.Series({"p_a": "1.5", "p_b": 2})

        self.assertEqual(_extract_params(row, ["a", "b"]), {"a": 1.5, "b": 2.0})

        with self.assertRaises(KeyError):
            _extract_params(row, ["a", "missing"])

    def test_extract_state_helpers_preserve_declared_order(self):
        row = pd.Series({"state_S": "10.0", "state_R": 20, "state_Q": np.nan})

        state_vec = _extract_state_vector(row, ["S", "R"])
        np.testing.assert_allclose(state_vec, np.array([10.0, 20.0]))
        self.assertEqual(_extract_state_dict(row, ["S", "R"]), {"S": 10.0, "R": 20.0})

        with self.assertRaises(KeyError):
            _extract_state_vector(row, ["S", "missing"])

    def test_classify_and_summarize_replay_diffs(self):
        self.assertEqual(_classify_replay_status(0.0, 1e-6), "pass")
        self.assertEqual(_classify_replay_status(1e-5, 1e-6), "fail")

        rows = pd.DataFrame([
            {"model": "GR4J", "replay_mode": "saved_state", "status": "pass", "abs_nse_diff": 0.0},
            {"model": "GR4J", "replay_mode": "saved_state", "status": "pass", "abs_nse_diff": 5e-7},
            {"model": "XAJ", "replay_mode": "warmup_recomputed", "status": "fail", "abs_nse_diff": 1e-4},
        ])
        summary = summarize_replay_rows(rows)

        gr4j = summary[(summary["model"] == "GR4J") & (summary["replay_mode"] == "saved_state")].iloc[0]
        self.assertEqual(int(gr4j["n"]), 2)
        self.assertEqual(int(gr4j["n_fail"]), 0)
        self.assertAlmostEqual(float(gr4j["max_abs_nse_diff"]), 5e-7)

        xaj = summary[(summary["model"] == "XAJ") & (summary["replay_mode"] == "warmup_recomputed")].iloc[0]
        self.assertEqual(int(xaj["n_fail"]), 1)


if __name__ == "__main__":
    unittest.main()
