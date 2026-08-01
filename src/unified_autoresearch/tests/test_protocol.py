import copy
import json
from pathlib import Path

import pytest


VALID_PROTOCOL = {
    "protocol_version": "development_v1",
    "forcing_product": "maurer",
    "dynamic_inputs": ["prcp", "tmin", "tmax", "srad", "vp"],
    "static_attribute_count": 27,
    "observed_discharge_policy": {
        "training_supervision": True,
        "validation_truth": True,
        "prediction_input": False,
    },
    "development_protocols": {
        "forward": {
            "train": ["1999-10-01", "2005-09-30"],
            "validation": ["2005-10-01", "2008-09-30"],
        },
        "reverse": {
            "train": ["2002-10-01", "2008-09-30"],
            "validation": ["1999-10-01", "2002-09-30"],
        },
    },
    "sealed_final_evaluation": ["1989-10-01", "1999-09-30"],
    "candidate_categories": ["deep_learning", "conceptual_rainfall_runoff", "fusion", "custom_python"],
}


def _write(tmp_path: Path, value: dict) -> Path:
    path = tmp_path / "development_v1.json"
    path.write_text(json.dumps(value), encoding="utf-8")
    return path


def test_exact_development_protocol_is_accepted(tmp_path):
    from unified_autoresearch.protocols.validation import load_and_validate_development_protocol

    loaded = load_and_validate_development_protocol(_write(tmp_path, VALID_PROTOCOL))
    assert loaded["protocol_version"] == "development_v1"
    assert loaded["forcing_product"] == "maurer"


@pytest.mark.parametrize(
    ("path", "replacement"),
    [
        (("forcing_product",), "daymet"),
        (("static_attribute_count",), 26),
        (("sealed_final_evaluation",), ["1990-01-01", "1999-09-30"]),
        (("development_protocols", "forward", "train"), ["1999-10-02", "2005-09-30"]),
        (("observed_discharge_policy", "prediction_input"), True),
    ],
)
def test_protocol_drift_is_rejected(tmp_path, path, replacement):
    from unified_autoresearch.protocols.validation import load_and_validate_development_protocol

    changed = copy.deepcopy(VALID_PROTOCOL)
    target = changed
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = replacement

    with pytest.raises(ValueError, match="frozen development protocol mismatch"):
        load_and_validate_development_protocol(_write(tmp_path, changed))


def test_protocol_rejects_dates_inside_sealed_final_evaluation(tmp_path):
    from unified_autoresearch.protocols.validation import load_and_validate_development_protocol

    changed = copy.deepcopy(VALID_PROTOCOL)
    changed["development_protocols"]["reverse"]["validation"] = ["1999-09-29", "2002-09-30"]
    with pytest.raises(ValueError, match="frozen development protocol mismatch"):
        load_and_validate_development_protocol(_write(tmp_path, changed))

