"""Small shared, non-tensor evidence primitives. No import-time filesystem access."""
from __future__ import annotations

import gzip
import hashlib
import json
import os
from pathlib import Path

FAMILY = Path(__file__).resolve().parent
REMOTE = "/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908"
OUTPUT_FAMILY = (Path("G:/github/pycharm/projects/kalmannet/experiments/optimize_hyper_parameters/wrr_model_selection_20260908")
                 if os.name == "nt" else Path(REMOTE))
METRIC = "validation_scoring.pooled_mean_leads_1_12_corrected_def"
NUMERIC_ERROR = "Exceeded max NaN recoveries in this epoch"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def canonical(value):
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_hash(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_json(path):
    # Duplicate JSON keys must not silently override identity fields.
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, f"Duplicate JSON key {key}")
            result[key] = value
        return result
    return json.loads(Path(path).read_bytes(), object_pairs_hook=pairs)


def immutable(path, data, *, root=OUTPUT_FAMILY):
    path, root = Path(path), Path(root).resolve()
    require(".." not in path.parts, "Traversal forbidden")
    require(path.resolve().is_relative_to(root) and path.resolve() != root, "Output outside family")
    require(not path.is_symlink(), "Symlink output forbidden")
    for parent in path.parents:
        require(not parent.is_symlink(), "Symlink output parent forbidden")
        if parent.resolve() == root:
            break
    # Even identical existing outputs consume their immutable name.
    with path.open("xb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def sealed(value):
    require("content_sha256" not in value, "Already sealed")
    return dict(value, content_sha256=digest(canonical(value)))


def verify_seal(value, *, kind=None):
    body = {key: item for key, item in value.items() if key != "content_sha256"}
    require(value.get("content_sha256") == digest(canonical(body)), "Modified evidence seal")
    if kind:
        require(value.get("kind") == kind, "Wrong evidence kind")
    return value


def compressed(value):
    return gzip.compress(canonical(value), mtime=0)
