"""Validate the exact, user-approved development protocol."""

from __future__ import annotations

import json
from pathlib import Path


FROZEN_DEVELOPMENT_PROTOCOL = {
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


def load_and_validate_development_protocol(path: str | Path) -> dict:
    """Load JSON and reject any drift from the approved development protocol."""
    loaded = json.loads(Path(path).read_text(encoding="utf-8"))
    if loaded != FROZEN_DEVELOPMENT_PROTOCOL:
        raise ValueError("frozen development protocol mismatch")
    return loaded

