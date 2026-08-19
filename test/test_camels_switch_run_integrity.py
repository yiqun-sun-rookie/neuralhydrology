import hashlib
import json
import sys
from pathlib import Path

import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from camels_switch_confirmation.run_integrity import (  # noqa: E402
    EXPECTED_ARMS,
    sha256_file,
    verify_parameter_run_config,
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def _write_json(path: Path, content: dict) -> None:
    path.write_text(
        json.dumps(content, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _refresh_registered_hash(
    config_path: Path,
    section: str,
    key: str,
    registered_file: Path,
) -> str:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    config[section][key] = _sha256(registered_file)
    _write_json(config_path, config)
    return _sha256(config_path)


def build_registered_fixture(
    root: Path,
    *,
    seeds: list[int] | None = None,
) -> tuple[Path, str]:
    data_root = root / "data"
    inputs = root / "inputs"
    registered = root / "registered"
    implementation = root / "implementation"
    for directory in (data_root, inputs, registered, implementation):
        directory.mkdir(parents=True, exist_ok=True)

    basin_id = "01022500"
    forcing = data_root / "forcing.txt"
    streamflow = data_root / "streamflow.txt"
    topography = data_root / "topography.txt"
    loader = implementation / "loader.py"
    parameter_table = inputs / "parameters.csv"
    precheck_table = inputs / "g1.csv"
    implementation_file = implementation / "runner.py"
    forcing.write_text("forcing", encoding="utf-8")
    streamflow.write_text("streamflow", encoding="utf-8")
    topography.write_text("topography", encoding="utf-8")
    loader.write_text("def load():\n    return None\n", encoding="utf-8")
    parameter_table.write_text("basin_id,p_parFC\n01022500,100\n", encoding="utf-8")
    precheck_table.write_text("basin_id,sigma_obs\n01022500,0.1\n", encoding="utf-8")
    implementation_file.write_text("VERSION = 1\n", encoding="utf-8")

    basin_list = registered / "basins.csv"
    pd.DataFrame({"basin_id": [basin_id]}).to_csv(basin_list, index=False)
    coverage = registered / "coverage.csv"
    pd.DataFrame(
        {
            "basin_id": [basin_id],
            "n_days": [1260],
            "first_date": ["1989-10-01"],
            "last_date": ["1993-03-13"],
            "finite_prcp": [True],
            "finite_ep": [True],
            "finite_tmean": [True],
            "all_required_forcing_finite": [True],
        }
    ).to_csv(coverage, index=False)

    raw_manifest = registered / "raw-inputs.csv"
    rows = []
    for category, path, row_basin_id in (
        ("maurer_forcing", forcing, basin_id),
        ("usgs_streamflow", streamflow, basin_id),
        ("camels_topography", topography, ""),
        ("forcing_loader_source", loader, ""),
        ("parameter_table", parameter_table, ""),
        ("g1_precheck_table", precheck_table, ""),
    ):
        rows.append(
            {
                "category": category,
                "basin_id": row_basin_id,
                "relative_path": path.relative_to(root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": _sha256(path),
            }
        )
    pd.DataFrame(rows).to_csv(raw_manifest, index=False)

    config = {
        "experiment_id": "CAMELS_PARFC_STATE_INTERACTION_TEST",
        "configuration_status": (
            "registered_exploratory_design_not_validation_frozen"
        ),
        "inputs": {
            "parameter_table": parameter_table.relative_to(root).as_posix(),
            "parameter_table_sha256": _sha256(parameter_table),
            "g1_precheck_table": precheck_table.relative_to(root).as_posix(),
            "g1_precheck_table_sha256": _sha256(precheck_table),
            "data_root": data_root.relative_to(root).as_posix(),
            "raw_input_manifest": raw_manifest.relative_to(root).as_posix(),
            "raw_input_manifest_sha256": _sha256(raw_manifest),
            "forcing_coverage_table": coverage.relative_to(root).as_posix(),
            "forcing_coverage_table_sha256": _sha256(coverage),
            "forcing": "maurer",
            "pet_method": "oudin",
        },
        "truth": {
            "window_start": "1989-10-01",
            "window_end": "1993-03-13",
            "window_days": 1260,
            "stage_days": 180,
            "rotation": [0, 1, 2, 0, 2, 1, 0],
            "slz_lognormal_sigma": 0.02,
            "seed_entropy": 20260807,
        },
        "candidates": {
            "parameter": "parFC",
            "factors": [1.0, 0.5, 2.0],
            "bounds_preset": "v5",
        },
        "filter": {
            "q_scale": 3e-8,
            "q_structure": "lower_groundwater_state_only",
            "q_mode": "fixed",
            "q_state_multiplier": 1.0,
            "observation_variance_multiplier": 1.0,
            "transition_diagonal": 0.98,
            "initial_covariance_fraction": 0.001,
        },
        "event_rule": {
            "response_window_days": 30,
            "consecutive_days": 5,
            "probability_threshold_exclusive": 0.5,
            "margin_inclusive": 0.1,
        },
        "seeds": {
            "design": [0, 1] if seeds is None else seeds,
            "reserved_validation_not_authorized": [2, 3],
        },
        "design_selection": {
            "basin_count": 1,
            "basin_list": basin_list.relative_to(root).as_posix(),
            "basin_list_sha256": _sha256(basin_list),
        },
        "arms": list(EXPECTED_ARMS),
        "implementation": {
            "parameter_runner": {
                "path": implementation_file.relative_to(root).as_posix(),
                "sha256": _sha256(implementation_file),
            }
        },
        "outputs": {"root": "outputs/registered-run"},
    }
    config_path = registered / "config.json"
    _write_json(config_path, config)
    return config_path, _sha256(config_path)


def test_verify_parameter_run_config_rejects_configuration_hash_change(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path)
    config_path.write_text(
        config_path.read_text(encoding="utf-8") + "\n",
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="configuration SHA-256 changed"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_raw_input_hash_change(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path)
    (tmp_path / "data" / "forcing.txt").write_text("changed", encoding="utf-8")

    with pytest.raises(ValueError, match="input file SHA-256 changed"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_reserved_validation_seed(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path, seeds=[0, 2])

    with pytest.raises(ValueError, match=r"design seeds must be exactly \[0, 1\]"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_filter_contract_drift(tmp_path):
    config_path, _ = build_registered_fixture(tmp_path)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    config["filter"]["q_scale"] = 1e-8
    _write_json(config_path, config)

    with pytest.raises(ValueError, match="registered filter contract changed"):
        verify_parameter_run_config(tmp_path, config_path, _sha256(config_path))


def test_verify_parameter_run_config_returns_exact_registered_identity(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path)

    verified = verify_parameter_run_config(tmp_path, config_path, expected_hash)

    assert verified.experiment_id == "CAMELS_PARFC_STATE_INTERACTION_TEST"
    assert verified.basin_ids == ("01022500",)
    assert [arm["arm_id"] for arm in verified.arms] == ["A", "B", "C"]
    assert verified.configuration_status == (
        "registered_exploratory_design_not_validation_frozen"
    )
    assert verified.data_root == (tmp_path / "data").resolve()
    assert verified.output_root == (tmp_path / "outputs" / "registered-run").resolve()
    assert verified.registered_hashes["raw_input_manifest_rows"] == 6
    assert sha256_file(config_path) == expected_hash


def test_verify_parameter_run_config_rejects_manifest_missing_column(tmp_path):
    config_path, _ = build_registered_fixture(tmp_path)
    manifest = tmp_path / "registered" / "raw-inputs.csv"
    frame = pd.read_csv(manifest)
    frame.drop(columns=["sha256"]).to_csv(manifest, index=False)
    expected_hash = _refresh_registered_hash(
        config_path,
        "inputs",
        "raw_input_manifest_sha256",
        manifest,
    )

    with pytest.raises(ValueError, match="manifest missing required columns"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_duplicate_basin(tmp_path):
    config_path, _ = build_registered_fixture(tmp_path)
    basin_list = tmp_path / "registered" / "basins.csv"
    pd.DataFrame({"basin_id": ["01022500", "01022500"]}).to_csv(
        basin_list,
        index=False,
    )
    expected_hash = _refresh_registered_hash(
        config_path,
        "design_selection",
        "basin_list_sha256",
        basin_list,
    )

    with pytest.raises(ValueError, match="basin list contains duplicates"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_coverage_change(tmp_path):
    config_path, _ = build_registered_fixture(tmp_path)
    coverage = tmp_path / "registered" / "coverage.csv"
    frame = pd.read_csv(coverage)
    frame.loc[0, "n_days"] = 1259
    frame.to_csv(coverage, index=False)
    expected_hash = _refresh_registered_hash(
        config_path,
        "inputs",
        "forcing_coverage_table_sha256",
        coverage,
    )

    with pytest.raises(ValueError, match="forcing coverage contract failed"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_implementation_drift(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path)
    (tmp_path / "implementation" / "runner.py").write_text(
        "VERSION = 2\n",
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="implementation file SHA-256 changed"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_preexisting_output_root(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path)
    (tmp_path / "outputs" / "registered-run").mkdir(parents=True)

    with pytest.raises(FileExistsError, match="output root already exists"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_parent_traversing_registered_path(
    tmp_path,
):
    config_path, _ = build_registered_fixture(tmp_path)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    config["inputs"]["parameter_table"] = "../parameters.csv"
    _write_json(config_path, config)
    expected_hash = _sha256(config_path)

    with pytest.raises(ValueError, match="repository-relative path"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)
