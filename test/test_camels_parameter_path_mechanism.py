import hashlib
import json
import math
import platform
import sys
from pathlib import Path
from types import SimpleNamespace

import pandas as pd
import pytest
import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

import camels_switch_confirmation.run_parameter_path_mechanism as runner  # noqa: E402
import camels_switch_confirmation.verify_parameter_path_mechanism as independent_verifier  # noqa: E402
from camels_switch_confirmation.g1_precheck import (  # noqa: E402
    PARAM_KEYS,
    STATE_NAMES as HYDRO_STATE_NAMES,
)
from hbv_joint_uncertainty.hbv_adapter import (  # noqa: E402
    STATE_NAMES as FULL_STATE_NAMES,
)


IMPLEMENTATION_ROLES = (
    "g2_switch_confirmation",
    "imm",
    "hbv_state_mapping",
    "preflight",
    "hbv_adapter",
    "sigma_filter",
    "bank",
    "g1_precheck",
    "data_loader",
    "hbv_model_and_bounds",
    "batch_control",
    "mechanism_runner",
    "mechanism_tests",
    "preregistration",
    "mechanism_plan",
    "mechanism_verifier",
    "mechanism_verifier_tests",
)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_json(path: Path, value: dict) -> str:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    return _sha(path)


def _case(tmp_path: Path) -> dict:
    data_root = tmp_path / "data"
    data_root.mkdir()
    results_root = tmp_path / "results" / "23_camels_switch_confirmation"
    source_root = (
        results_root / "registered_source_experiment" / "arms" / "C" / "probs"
    )
    source_root.mkdir(parents=True)
    basin_ids = [f"01{index:06d}" for index in range(1, 6)]
    task_rows = []
    for basin_id in basin_ids:
        for seed in (0, 1):
            source = source_root / f"{basin_id}_s{seed}.npz"
            np.savez_compressed(
                source,
                probabilities=np.full((1260, 3), 1.0 / 3.0),
                log_probabilities=np.full((1260, 3), -np.log(3.0)),
                truth_q=np.ones(1260),
                observations=np.ones(1260),
                basin_id=np.asarray(basin_id),
                seed=np.asarray(seed),
                arm_id=np.asarray("C"),
                state_interaction_mode=np.asarray("full"),
                parameter_state_mapping=np.asarray("conservative_parfc"),
                filter_process_variance_scale=np.asarray(3e-8),
                filter_process_covariance_structure=np.asarray(
                    "lower_groundwater_state_only"
                ),
                filter_q_mode=np.asarray("fixed"),
                filter_q_state_multiplier=np.asarray(1.0),
                filter_observation_variance_multiplier=np.asarray(1.0),
            )
            task_rows.append(
                {
                    "basin_id": basin_id,
                    "seed": seed,
                    "arm_id": "C",
                    "source_probability_path": source.relative_to(tmp_path).as_posix(),
                    "source_probability_bytes": source.stat().st_size,
                    "source_probability_sha256": _sha(source),
                }
            )
    tasks = tmp_path / "tasks.csv"
    pd.DataFrame(task_rows).to_csv(tasks, index=False)

    parameter_rows = []
    for index, basin_id in enumerate(basin_ids):
        row = {"basin_id": basin_id}
        row.update({f"p_{key}": index + 1.0 for key in PARAM_KEYS})
        row.update({f"state_{name}": index + 2.0 for name in HYDRO_STATE_NAMES})
        parameter_rows.append(row)
    parameters = tmp_path / "parameters.csv"
    pd.DataFrame(parameter_rows).to_csv(parameters, index=False)
    g1 = tmp_path / "g1.csv"
    pd.DataFrame(
        {"basin_id": basin_ids, "sigma_obs": [0.1] * len(basin_ids)}
    ).to_csv(g1, index=False)
    raw_input = data_root / "raw_input.txt"
    raw_input.write_text("registered raw input\n", encoding="utf-8")
    raw_manifest = tmp_path / "raw_input_manifest.csv"
    pd.DataFrame(
        [
            {
                "relative_path": raw_input.relative_to(tmp_path).as_posix(),
                "bytes": raw_input.stat().st_size,
                "sha256": _sha(raw_input),
            }
        ]
    ).to_csv(raw_manifest, index=False)

    initial_manifest = tmp_path / "initial_moment_manifest.npz"
    initial_task_count = len(task_rows)
    initial_probabilities = np.full((initial_task_count, 3), 1.0 / 3.0)
    initial_states = np.empty((initial_task_count, 3, len(FULL_STATE_NAMES)))
    initial_covariances = np.empty(
        (
            initial_task_count,
            3,
            len(FULL_STATE_NAMES),
            len(FULL_STATE_NAMES),
        )
    )
    for task_index, task in enumerate(task_rows):
        basin_index = basin_ids.index(task["basin_id"])
        initial_states[task_index] = basin_index + 2.0
        initial_covariances[task_index] = np.eye(len(FULL_STATE_NAMES))
    np.savez_compressed(
        initial_manifest,
        basin_id=np.asarray([row["basin_id"] for row in task_rows]),
        seed=np.asarray([row["seed"] for row in task_rows], dtype=np.int64),
        initial_probabilities=initial_probabilities,
        initial_states=initial_states,
        initial_covariances=initial_covariances,
        initial_probability_axis_order=np.asarray(["task", "candidate"]),
        initial_state_axis_order=np.asarray(["task", "candidate", "state"]),
        initial_covariance_axis_order=np.asarray(
            ["task", "candidate", "state_row", "state_column"]
        ),
    )

    output = results_root / "test_parameter_path_output"
    implementation = {}
    implementation_root = tmp_path / "implementation"
    implementation_root.mkdir()
    for role in IMPLEMENTATION_ROLES:
        path = implementation_root / f"{role}.txt"
        path.write_text(role + "\n", encoding="utf-8")
        implementation[role] = {
            "path": path.relative_to(tmp_path).as_posix(),
            "sha256": _sha(path),
        }
    config = {
        "experiment_id": "TEST_PARAMETER_PATH_MECHANISM",
        "configuration_status": "mechanism_check_design_seeds_not_validation",
        "inputs": {
            "task_table": tasks.relative_to(tmp_path).as_posix(),
            "task_table_sha256": _sha(tasks),
            "parameter_table": parameters.relative_to(tmp_path).as_posix(),
            "parameter_table_sha256": _sha(parameters),
            "g1_precheck_table": g1.relative_to(tmp_path).as_posix(),
            "g1_precheck_table_sha256": _sha(g1),
            "raw_input_manifest": raw_manifest.relative_to(tmp_path).as_posix(),
            "raw_input_manifest_sha256": _sha(raw_manifest),
            "initial_moment_manifest": initial_manifest.relative_to(tmp_path).as_posix(),
            "initial_moment_manifest_sha256": _sha(initial_manifest),
            "data_root": data_root.relative_to(tmp_path).as_posix(),
        },
        "filter": {
            "q_scale": 3e-8,
            "q_structure": "lower_groundwater_state_only",
            "q_mode": "fixed",
            "q_state_multiplier": 1.0,
            "observation_variance_multiplier": 1.0,
        },
        "arms": [
            {
                "arm_id": "C",
                "interaction_mode": "full",
                "parameter_state_mapping": "conservative_parfc",
            },
            {
                "arm_id": "P",
                "interaction_mode": "pairwise_path_postcollapse",
                "parameter_state_mapping": "conservative_parfc",
            },
        ],
        "implementation": implementation,
        "runtime": {
            "python_executable": str(Path(sys.executable).resolve()),
            "python_executable_sha256": _sha(Path(sys.executable).resolve()),
            "python_version": sys.version,
            "python_implementation": sys.implementation.name,
            "python_compiler": platform.python_compiler(),
            "machine": platform.machine(),
            "numpy_version": np.__version__,
            "byteorder": sys.byteorder,
            "double_format": float.__getformat__("double"),
            "float_radix": sys.float_info.radix,
            "float_mant_dig": sys.float_info.mant_dig,
            "float_rounds": sys.float_info.rounds,
            "ulp_one_hex": math.ulp(1.0).hex(),
            "ulp_zero_hex": math.ulp(0.0).hex(),
            "nextafter_zero_hex": math.nextafter(0.0, 1.0).hex(),
            "math_fma_available": hasattr(math, "fma"),
        },
        "outputs": {"root": output.relative_to(tmp_path).as_posix()},
    }
    config_path = tmp_path / "config.json"
    config_sha = _write_json(config_path, config)
    return {
        "root": tmp_path,
        "tasks": tasks,
        "parameters": parameters,
        "g1": g1,
        "raw_manifest": raw_manifest,
        "raw_input": raw_input,
        "initial_manifest": initial_manifest,
        "config": config,
        "config_path": config_path,
        "config_sha": config_sha,
        "output": output,
    }


def _successful_execution(work):
    records = [
        {
            "task_index": index,
            "basin_id": item[0],
            "seed": item[1],
            "arm_id": item[-1],
            "run_status": "success",
            "error_message": "",
        }
        for index, item in enumerate(work)
    ]
    return SimpleNamespace(
        records=records,
        execution_status="complete",
        first_failure=None,
        n_planned=len(work),
        n_submitted=len(work),
        n_cancelled_before_start=0,
        n_not_submitted_after_failure=0,
        n_completed_after_stop=0,
    )


def _rewrite_first_source(case: dict, updates: dict) -> str:
    tasks = pd.read_csv(case["tasks"], dtype={"basin_id": str})
    source = case["root"] / tasks.loc[0, "source_probability_path"]
    with np.load(source, allow_pickle=False) as archive:
        values = {key: archive[key] for key in archive.files}
    for key, value in updates.items():
        if value is None:
            values.pop(key, None)
        else:
            values[key] = np.asarray(value)
    np.savez_compressed(source, **values)
    tasks.loc[0, "source_probability_bytes"] = source.stat().st_size
    tasks.loc[0, "source_probability_sha256"] = _sha(source)
    tasks.to_csv(case["tasks"], index=False)
    case["config"]["inputs"]["task_table_sha256"] = _sha(case["tasks"])
    return _write_json(case["config_path"], case["config"])


def _rewrite_initial_manifest(case: dict, updates: dict) -> str:
    with np.load(case["initial_manifest"], allow_pickle=False) as archive:
        values = {key: archive[key] for key in archive.files}
    for key, value in updates.items():
        values[key] = np.asarray(value)
    np.savez_compressed(case["initial_manifest"], **values)
    case["config"]["inputs"]["initial_moment_manifest_sha256"] = _sha(
        case["initial_manifest"]
    )
    return _write_json(case["config_path"], case["config"])


def test_initial_moment_manifest_uses_one_fifteen_state_contract(tmp_path):
    case = _case(tmp_path)

    verified = runner.verify_parameter_path_mechanism(
        case["root"],
        case["config_path"],
        case["config_sha"],
    )
    expected_keys = {
        (str(row.basin_id), int(row.seed))
        for row in verified.task_table.itertuples(index=False)
    }
    initial_moments = independent_verifier._load_initial_moment_manifest(
        case["root"],
        case["config"]["inputs"],
        expected_keys,
    )

    assert len(FULL_STATE_NAMES) == 15
    assert len(initial_moments) == 10
    for probabilities, states, covariances in initial_moments.values():
        assert probabilities.shape == (3,)
        assert states.shape == (3, len(FULL_STATE_NAMES))
        assert covariances.shape == (
            3,
            len(FULL_STATE_NAMES),
            len(FULL_STATE_NAMES),
        )


def test_five_state_initial_moment_manifest_is_rejected_by_both_contracts(
    tmp_path,
):
    case = _case(tmp_path)
    with np.load(case["initial_manifest"], allow_pickle=False) as archive:
        five_state_values = {
            "initial_states": archive["initial_states"][
                :, :, : len(HYDRO_STATE_NAMES)
            ],
            "initial_covariances": archive["initial_covariances"][
                :,
                :,
                : len(HYDRO_STATE_NAMES),
                : len(HYDRO_STATE_NAMES),
            ],
        }
    config_sha = _rewrite_initial_manifest(case, five_state_values)
    tasks = pd.read_csv(case["tasks"], dtype={"basin_id": str})
    expected_keys = {
        (str(row.basin_id), int(row.seed))
        for row in tasks.itertuples(index=False)
    }

    with pytest.raises(ValueError, match="initial_states must have shape"):
        runner.verify_parameter_path_mechanism(
            case["root"],
            case["config_path"],
            config_sha,
        )
    with pytest.raises(
        ValueError,
        match="initial-moment manifest array shapes changed",
    ):
        independent_verifier._load_initial_moment_manifest(
            case["root"],
            case["config"]["inputs"],
            expected_keys,
        )


def test_success_submits_one_twenty_task_batch_and_writes_audit(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    calls = []

    def execute(**kwargs):
        calls.append(kwargs)
        return _successful_execution(kwargs["work"])

    monkeypatch.setattr(runner, "execute_fail_fast", execute)

    summary = runner.run_parameter_path_mechanism(
        case["config_path"], case["config_sha"], workers=3
    )

    assert summary["execution_status"] == "complete"
    assert len(calls) == 1
    work = calls[0]["work"]
    assert len(work) == 20
    assert [item[-1] for item in work] == ["C"] * 10 + ["P"] * 10
    assert {item[1] for item in work} == {0, 1}
    assert all(item[4:9] == (3e-8, "lower_groundwater_state_only", "fixed", 1.0, 1.0) for item in work)
    assert all(item[3]["sigma_obs"] == 0.1 for item in work)
    assert {item[9] for item in work[:10]} == {"full"}
    assert {item[9] for item in work[10:]} == {"pairwise_path_postcollapse"}
    assert (case["output"] / "arms" / "C" / "tasks.csv").is_file()
    assert (case["output"] / "arms" / "P" / "tasks.csv").is_file()
    assert (case["output"] / "runner_summary.json").is_file()


def test_config_hash_mismatch_stops_before_output(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])

    with pytest.raises(ValueError, match="configuration SHA-256 changed"):
        runner.run_parameter_path_mechanism(
            case["config_path"], "0" * 64, workers=1
        )

    assert not case["output"].exists()


@pytest.mark.parametrize(
    ("key", "bad_value"),
    [
        ("python_version", "wrong-python"),
        ("numpy_version", "wrong-numpy"),
        ("double_format", "unknown"),
        ("float_mant_dig", 52),
        ("float_rounds", 0),
        ("ulp_zero_hex", "0x0.0p+0"),
        ("math_fma_available", True),
    ],
)
def test_runtime_contract_change_stops_before_output(
    tmp_path,
    monkeypatch,
    key,
    bad_value,
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    case["config"]["runtime"][key] = bad_value
    expected = _write_json(case["config_path"], case["config"])

    with pytest.raises(ValueError, match="runtime"):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not case["output"].exists()


def test_registered_and_observed_runtime_cannot_drift_together(
    tmp_path,
    monkeypatch,
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    observed = runner._observed_runtime_contract()
    observed["numpy_version"] = "9.9.9"
    case["config"]["runtime"]["numpy_version"] = "9.9.9"
    expected = _write_json(case["config_path"], case["config"])
    monkeypatch.setattr(runner, "_observed_runtime_contract", lambda: observed)

    with pytest.raises(ValueError, match="fixed runtime semantics changed"):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not case["output"].exists()


def test_python_executable_hash_change_stops_before_output(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    case["config"]["runtime"]["python_executable_sha256"] = "0" * 64
    expected = _write_json(case["config_path"], case["config"])

    with pytest.raises(ValueError, match="Python executable SHA-256 changed"):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not case["output"].exists()


def test_initial_moment_manifest_hash_change_stops_before_output(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    case["config"]["inputs"]["initial_moment_manifest_sha256"] = "0" * 64
    expected = _write_json(case["config_path"], case["config"])

    with pytest.raises(ValueError, match="initial moment manifest SHA-256 changed"):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not case["output"].exists()


def test_initial_moment_manifest_identity_change_stops_before_output(
    tmp_path,
    monkeypatch,
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    with np.load(case["initial_manifest"], allow_pickle=False) as archive:
        values = {key: archive[key] for key in archive.files}
    values["seed"] = values["seed"].copy()
    values["seed"][0] = 9
    np.savez_compressed(case["initial_manifest"], **values)
    case["config"]["inputs"]["initial_moment_manifest_sha256"] = _sha(
        case["initial_manifest"]
    )
    expected = _write_json(case["config_path"], case["config"])

    with pytest.raises(ValueError, match="initial moment manifest task identities"):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not case["output"].exists()


def test_initial_moment_manifest_shape_change_stops_before_output(
    tmp_path,
    monkeypatch,
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    with np.load(case["initial_manifest"], allow_pickle=False) as archive:
        values = {key: archive[key] for key in archive.files}
    values["initial_states"] = values["initial_states"][:, :, :-1]
    np.savez_compressed(case["initial_manifest"], **values)
    case["config"]["inputs"]["initial_moment_manifest_sha256"] = _sha(
        case["initial_manifest"]
    )
    expected = _write_json(case["config_path"], case["config"])

    with pytest.raises(ValueError, match="initial_states must have shape"):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not case["output"].exists()


@pytest.mark.parametrize(
    ("field", "index", "value", "message"),
    [
        (
            "initial_probabilities",
            (0, 0),
            np.nan,
            "initial probabilities must be finite",
        ),
        (
            "initial_states",
            (0, 0, 0),
            np.inf,
            "initial states and covariances must be finite",
        ),
        (
            "initial_covariances",
            (0, 0, 0, 0),
            -np.inf,
            "initial states and covariances must be finite",
        ),
    ],
)
def test_initial_moment_manifest_nonfinite_stops_before_output(
    tmp_path,
    monkeypatch,
    field,
    index,
    value,
    message,
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    with np.load(case["initial_manifest"], allow_pickle=False) as archive:
        changed = archive[field].copy()
    changed[index] = value
    expected = _rewrite_initial_manifest(case, {field: changed})

    with pytest.raises(ValueError, match=message):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not case["output"].exists()


def test_initial_moment_manifest_nonsymmetric_covariance_stops_before_output(
    tmp_path,
    monkeypatch,
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    with np.load(case["initial_manifest"], allow_pickle=False) as archive:
        changed = archive["initial_covariances"].copy()
    changed[0, 0, 0, 1] = 0.25
    expected = _rewrite_initial_manifest(
        case,
        {"initial_covariances": changed},
    )

    with pytest.raises(ValueError, match="initial covariances must be symmetric"):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not case["output"].exists()


@pytest.mark.parametrize(
    ("field", "changed", "message"),
    [
        (
            "initial_probability_axis_order",
            ["candidate", "task"],
            "initial probability axis order changed",
        ),
        (
            "initial_state_axis_order",
            ["task", "state", "candidate"],
            "initial state axis order changed",
        ),
        (
            "initial_covariance_axis_order",
            ["task", "candidate", "state_column", "state_row"],
            "initial covariance axis order changed",
        ),
    ],
)
def test_initial_moment_manifest_axis_change_stops_before_output(
    tmp_path,
    monkeypatch,
    field,
    changed,
    message,
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    expected = _rewrite_initial_manifest(case, {field: changed})

    with pytest.raises(ValueError, match=message):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not case["output"].exists()


def test_task_hash_change_stops_before_output(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    case["tasks"].write_text(
        case["tasks"].read_text(encoding="utf-8") + "\n", encoding="utf-8"
    )

    with pytest.raises(ValueError, match="task table SHA-256 changed"):
        runner.run_parameter_path_mechanism(
            case["config_path"], case["config_sha"], workers=1
        )

    assert not case["output"].exists()


@pytest.mark.parametrize(
    "artifact, message",
    [
        ("parameters", "parameter table SHA-256 changed"),
        ("g1", "G1 precheck table SHA-256 changed"),
        ("raw_manifest", "raw-input manifest SHA-256 changed"),
    ],
)
def test_registered_input_file_change_stops_before_output(
    tmp_path, monkeypatch, artifact, message
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    path = case[artifact]
    original = path.read_bytes()
    path.write_bytes(original.replace(b"1.0", b"9.0", 1) if b"1.0" in original else original + b"x")

    with pytest.raises(ValueError, match=message):
        runner.verify_parameter_path_mechanism(
            case["root"], case["config_path"], case["config_sha"]
        )

    assert not case["output"].exists()


def test_manifest_registered_file_change_stops_before_output(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    original = case["raw_input"].read_bytes()
    case["raw_input"].write_bytes(b"z" * len(original))

    with pytest.raises(ValueError, match="raw input SHA-256 changed"):
        runner.verify_parameter_path_mechanism(
            case["root"], case["config_path"], case["config_sha"]
        )

    assert not case["output"].exists()


@pytest.mark.parametrize(
    "updates, message",
    [
        ({"basin_id": "99999999"}, "embedded basin_id differs"),
        ({"seed": 9}, "embedded seed differs"),
    ],
)
def test_source_probability_identity_mismatch_stops_before_output(
    tmp_path, monkeypatch, updates, message
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    expected = _rewrite_first_source(case, updates)

    with pytest.raises(ValueError, match=message):
        runner.verify_parameter_path_mechanism(
            case["root"], case["config_path"], expected
        )

    assert not case["output"].exists()


@pytest.mark.parametrize(
    "field, value",
    [
        ("arm_id", "P"),
        ("state_interaction_mode", "parameter_grouped"),
        ("parameter_state_mapping", "legacy_projection"),
    ],
)
def test_source_probability_method_mismatch_stops_before_output(
    tmp_path, monkeypatch, field, value
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    expected = _rewrite_first_source(case, {field: value})

    with pytest.raises(ValueError, match=f"embedded {field} differs"):
        runner.verify_parameter_path_mechanism(
            case["root"], case["config_path"], expected
        )

    assert not case["output"].exists()


@pytest.mark.parametrize(
    "field, value",
    [
        ("filter_process_variance_scale", 1e-8),
        ("filter_process_covariance_structure", "all_hydrologic_states"),
        ("filter_q_mode", "state_dependent"),
        ("filter_q_state_multiplier", 2.0),
        ("filter_observation_variance_multiplier", 2.0),
    ],
)
def test_source_probability_noise_mismatch_stops_before_output(
    tmp_path, monkeypatch, field, value
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    expected = _rewrite_first_source(case, {field: value})

    with pytest.raises(ValueError, match=f"embedded {field} differs"):
        runner.verify_parameter_path_mechanism(
            case["root"], case["config_path"], expected
        )

    assert not case["output"].exists()


@pytest.mark.parametrize(
    "updates, message",
    [
        ({"observations": None}, "lacks required fields"),
        ({"probabilities": np.full((1259, 3), 1.0 / 3.0)}, "probabilities shape differs"),
    ],
)
def test_source_probability_required_array_contract_stops_before_output(
    tmp_path, monkeypatch, updates, message
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    expected = _rewrite_first_source(case, updates)

    with pytest.raises(ValueError, match=message):
        runner.verify_parameter_path_mechanism(
            case["root"], case["config_path"], expected
        )

    assert not case["output"].exists()


def test_implementation_hash_change_stops_before_output(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    registered = case["config"]["implementation"]["imm"]
    (case["root"] / registered["path"]).write_text("changed\n", encoding="utf-8")

    with pytest.raises(ValueError, match="implementation file SHA-256 changed"):
        runner.run_parameter_path_mechanism(
            case["config_path"], case["config_sha"], workers=1
        )

    assert not case["output"].exists()


@pytest.mark.parametrize("content, message", [
    (b"different-same", "source probability SHA-256 changed"),
    (b"x", "source probability byte count changed"),
])
def test_source_probability_change_stops_before_output(
    tmp_path, monkeypatch, content, message
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    tasks = pd.read_csv(case["tasks"], dtype={"basin_id": str})
    source = case["root"] / tasks.loc[0, "source_probability_path"]
    if len(content) != source.stat().st_size and "SHA" in message:
        content = b"z" * source.stat().st_size
    source.write_bytes(content)

    with pytest.raises(ValueError, match=message):
        runner.run_parameter_path_mechanism(
            case["config_path"], case["config_sha"], workers=1
        )

    assert not case["output"].exists()


@pytest.mark.parametrize("mutation, message", [
    ("duplicate", "exactly 10 unique basin-seed tasks"),
    ("missing", "exactly 10 unique basin-seed tasks"),
    ("seed", "design seeds must be only 0 or 1"),
    ("arm", "source arm must be C"),
])
def test_invalid_task_contract_stops_before_output(
    tmp_path, monkeypatch, mutation, message
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    frame = pd.read_csv(case["tasks"], dtype={"basin_id": str})
    if mutation == "duplicate":
        frame.iloc[-1] = frame.iloc[0]
    elif mutation == "missing":
        frame = frame.iloc[:-1]
    elif mutation == "seed":
        frame.loc[0, "seed"] = 2
    else:
        frame.loc[0, "arm_id"] = "P"
    frame.to_csv(case["tasks"], index=False)
    case["config"]["inputs"]["task_table_sha256"] = _sha(case["tasks"])
    expected = _write_json(case["config_path"], case["config"])

    with pytest.raises(ValueError, match=message):
        runner.run_parameter_path_mechanism(case["config_path"], expected, workers=1)

    assert not case["output"].exists()


@pytest.mark.parametrize("section,key,value", [
    ("filter", "q_scale", 1e-8),
    ("filter", "q_structure", "all_states"),
    ("filter", "q_mode", "state_dependent"),
    ("filter", "observation_variance_multiplier", 2.0),
    ("arms", 0, {"arm_id": "C", "interaction_mode": "parameter_grouped", "parameter_state_mapping": "conservative_parfc"}),
])
def test_wrong_arm_or_filter_setting_stops_before_output(
    tmp_path, monkeypatch, section, key, value
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    if section == "arms":
        case["config"][section][key] = value
    else:
        case["config"][section][key] = value
    expected = _write_json(case["config_path"], case["config"])

    with pytest.raises(ValueError, match="fixed (filter|arms) contract changed"):
        runner.run_parameter_path_mechanism(case["config_path"], expected, workers=1)

    assert not case["output"].exists()


def test_existing_output_stops_without_calling_workers(tmp_path, monkeypatch):
    case = _case(tmp_path)
    case["output"].mkdir()
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    monkeypatch.setattr(
        runner,
        "execute_fail_fast",
        lambda **_kwargs: pytest.fail("workers must not start"),
    )

    with pytest.raises(FileExistsError, match="output root already exists"):
        runner.run_parameter_path_mechanism(
            case["config_path"], case["config_sha"], workers=1
        )


def test_output_outside_registered_results_root_stops_before_output(
    tmp_path,
    monkeypatch,
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    outside = tmp_path / "outside_output"
    case["config"]["outputs"]["root"] = outside.relative_to(tmp_path).as_posix()
    expected = _write_json(case["config_path"], case["config"])

    with pytest.raises(ValueError, match="output root must resolve inside"):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not outside.exists()


@pytest.mark.parametrize(
    "experiment_name",
    [
        "registered_source_experiment",
        "camels_parfc_transition_path_03_mechanism10_s01_20260810_local",
        "camels_parfc_transition_path_03a_mechanism10_s01_20260810_local",
    ],
)
def test_output_inside_protected_evidence_stops_before_output(
    tmp_path,
    monkeypatch,
    experiment_name,
):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    protected_child = (
        tmp_path
        / "results"
        / "23_camels_switch_confirmation"
        / experiment_name
        / "new_attempt"
    )
    case["config"]["outputs"]["root"] = protected_child.relative_to(
        tmp_path
    ).as_posix()
    expected = _write_json(case["config_path"], case["config"])

    with pytest.raises(ValueError, match="protected source or prior-evidence"):
        runner.run_parameter_path_mechanism(
            case["config_path"], expected, workers=1
        )

    assert not protected_child.exists()


def test_resolved_output_escape_stops_before_output(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])
    outside = tmp_path.parent
    original_relative_path = runner._relative_path

    def escaped_relative_path(root, value, label):
        if label == "output root":
            return outside / "new_attempt"
        return original_relative_path(root, value, label)

    monkeypatch.setattr(runner, "_relative_path", escaped_relative_path)

    with pytest.raises(ValueError, match="output root must resolve inside"):
        runner.run_parameter_path_mechanism(
            case["config_path"], case["config_sha"], workers=1
        )

    assert not (outside / "new_attempt").exists()


def test_worker_failure_writes_summary_and_main_returns_one(tmp_path, monkeypatch):
    case = _case(tmp_path)
    monkeypatch.setattr(runner, "_REPO_ROOT", case["root"])

    def failed(**kwargs):
        execution = _successful_execution(kwargs["work"])
        execution.records[0]["run_status"] = "failed"
        execution.records[0]["error_message"] = "RuntimeError: boom"
        execution.execution_status = "failed_early"
        execution.first_failure = execution.records[0]
        return execution

    monkeypatch.setattr(runner, "execute_fail_fast", failed)

    code = runner.main(
        [
            "--config", str(case["config_path"]),
            "--expected-config-sha256", case["config_sha"],
            "--workers", "2",
        ]
    )

    assert code == 1
    summary = json.loads(
        (case["output"] / "runner_summary.json").read_text(encoding="utf-8")
    )
    assert summary["execution_status"] == "failed_early"
    assert summary["scientific_aggregation_status"] == "not_evaluated_incomplete_execution"
