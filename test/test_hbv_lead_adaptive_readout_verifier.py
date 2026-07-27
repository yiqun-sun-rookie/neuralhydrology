"""Independent recomputation tests for the formal readout evidence."""

from __future__ import annotations

import hashlib
import importlib
import inspect
import json
import shutil
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
FORMAL_OUTPUT = (
    REPO_ROOT
    / "results"
    / "23_hbv_multilead_joint_uncertainty"
    / "g3_lead_adaptive_readout_param_switch_v01"
)
VERIFIER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "verify_g3_lead_adaptive_readout"
)


def test_independent_verifier_recomputes_formal_negative_result():
    verifier = importlib.import_module(VERIFIER_MODULE)

    result = verifier.verify(FORMAL_OUTPUT)

    assert result["passed"] is True
    assert result["retention_decision"] == "reject"
    np.testing.assert_allclose(
        result["rmse"]["lead_adaptive"],
        [2.036829618526328, 3.643174851434231, 4.880102343618926],
        rtol=0.0,
        atol=1e-14,
    )
    np.testing.assert_allclose(
        result["rmse"]["full_posterior"],
        [1.9359163200141463, 3.633043338466265, 4.884323421466228],
        rtol=0.0,
        atol=1e-14,
    )
    np.testing.assert_allclose(
        result["rmse"]["none_posterior"],
        [2.0056994448202996, 3.8645890075017477, 4.9121791975397],
        rtol=0.0,
        atol=1e-14,
    )
    assert result["selection_accuracy"] == pytest.approx(88 / 96)
    assert result["multiday_normalized_mse_composite"]["ci_high"] == pytest.approx(
        0.021992244081710452
    )
    assert all(
        value is False
        for key, value in result["retention_gates"].items()
        if key != "retain"
    )
    assert result["retention_gates"]["retain"] is False


def test_verifier_is_independent_of_project_readout_and_summary_functions():
    verifier = importlib.import_module(VERIFIER_MODULE)
    source = inspect.getsource(verifier)

    assert "lead_adaptive_readout import" not in source
    assert "summarize_lead_adaptive_readout" not in source
    assert "summary.json" not in source


def _tampered_copy(tmp_path):
    destination = tmp_path / FORMAL_OUTPUT.name
    shutil.copytree(FORMAL_OUTPUT, destination)
    return destination


def _rewrite_evidence(directory, mutation):
    evidence_path = directory / "evidence.npz"
    with np.load(evidence_path, allow_pickle=False) as archive:
        arrays = {name: archive[name].copy() for name in archive.files}
    mutation(arrays)
    np.savez_compressed(evidence_path, **arrays)
    checksums_path = directory / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["evidence.npz"] = hashlib.sha256(
        evidence_path.read_bytes()
    ).hexdigest()
    checksums_path.write_text(
        json.dumps(checksums, indent=2, sort_keys=True),
        encoding="utf-8",
    )


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (
            lambda arrays: arrays["selected_candidate_indices"].__setitem__(
                (0, 0), 2
            ),
            "selected_candidate_indices",
        ),
        (
            lambda arrays: arrays["lead_adaptive_forecasts"].__setitem__(
                (0, 0, 0),
                arrays["lead_adaptive_forecasts"][0, 0, 0] + 0.25,
            ),
            "lead_adaptive_forecasts",
        ),
        (
            lambda arrays: arrays["bootstrap_indices"].fill(0),
            "interval",
        ),
        (
            lambda arrays: arrays[
                "lead_adaptive_minus_none_posterior_ci_high"
            ].__setitem__(
                0,
                arrays[
                    "lead_adaptive_minus_none_posterior_ci_high"
                ][0]
                + 0.25,
            ),
            "interval",
        ),
    ],
)
def test_verifier_rejects_semantic_tampering_even_with_updated_checksum(
    tmp_path,
    mutation,
    match,
):
    verifier = importlib.import_module(VERIFIER_MODULE)
    directory = _tampered_copy(tmp_path)
    _rewrite_evidence(directory, mutation)

    with pytest.raises(ValueError, match=match):
        verifier.verify(directory)


def test_verifier_rejects_checksum_manifest_extras(tmp_path):
    verifier = importlib.import_module(VERIFIER_MODULE)
    directory = _tampered_copy(tmp_path)
    extra = directory / "unregistered.txt"
    extra.write_text("extra", encoding="utf-8")

    with pytest.raises(ValueError, match="checksum"):
        verifier.verify(directory)
