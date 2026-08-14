"""03C Design90 runner: state-proportional SLZ process covariance fix.

Single-factor change against the frozen 03B contract: the filter process
covariance mode becomes ``lower_groundwater_state_proportional`` with
multiplier one (first-two-moment match to the truth's multiplicative SLZ
noise).  Every other factor -- candidates, task table, initial moments,
forcing, observations, Gaussian evidence, transition matrix, conservative
parFC mapping, both arms -- is inherited from the frozen 03B configuration
by hash equality.  Execution was authorized by an explicit user go on
2026-08-14 together with the dual-window (30-day primary, 90-day secondary)
event-reporting preregistration.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Mapping
from pathlib import Path

from camels_switch_confirmation import run_parameter_path_design90 as design
from camels_switch_confirmation import run_parameter_path_mechanism as base
from camels_switch_confirmation.batch_control import execute_fail_fast
from camels_switch_confirmation.g2_switch_confirmation import _run_one


_REPO_ROOT = Path(__file__).resolve().parents[2]

EXPERIMENT_ID = "CAMELS_PARFC_TRANSITION_PATH_03C_DESIGN90_PROPQ"
CONFIGURATION_STATUS = "design90_exploratory_propq_fix_design_seeds_not_validation"
EXPECTED_FILTER = {
    "q_scale": 3e-8,
    "q_structure": "lower_groundwater_state_only",
    "q_mode": "lower_groundwater_state_proportional",
    "q_state_multiplier": 1.0,
    "observation_variance_multiplier": 1.0,
}
SOURCE_03B_CONFIGURATION = Path(
    "src/camels_switch_confirmation/configs/"
    "camels_parfc_transition_path_03b_design90.json"
)
EXPECTED_03B_CONFIG_SHA256 = (
    "b7bd90e752738b4a9d766e0138e7d9007f97c18443cc7764e0bba6d0b5221669"
)
CONFIGURATION = Path(
    "src/camels_switch_confirmation/configs/"
    "camels_parfc_transition_path_03c_design90_propq.json"
)
PREREGISTRATION = Path(
    "docs/plans/2026-08-14-camels-parfc-transition-path-"
    "03c-design90-propq-prereg-v01.md"
)
OUTPUT_ROOT = Path(
    "results/23_camels_switch_confirmation/"
    "camels_parfc_transition_path_03c_design90_propq_s01_20260814_local"
)
MOTIVATING_EVIDENCE = {
    "day540_fifteen_state_counterfactual_summary": Path(
        "results/23_camels_switch_confirmation/"
        "camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_20260812_local/"
        "summary.json"
    ),
    "day540_sm_only_counterfactual_summary": Path(
        "results/23_camels_switch_confirmation/"
        "camels_parfc_day540_state_subset_counterfactual_07184000_s0_01_20260814_local/"
        "sm_only/summary.json"
    ),
    "day540_all_but_sm_counterfactual_summary": Path(
        "results/23_camels_switch_confirmation/"
        "camels_parfc_day540_state_subset_counterfactual_07184000_s0_01_20260814_local/"
        "all_but_sm/summary.json"
    ),
    "single_basin_propq_C_s0_summary": Path(
        "results/23_camels_switch_confirmation/"
        "camels_parfc_slz_state_proportional_q_07184000_01_20260814_local/"
        "C_s0/summary.json"
    ),
    "single_basin_propq_C_s1_summary": Path(
        "results/23_camels_switch_confirmation/"
        "camels_parfc_slz_state_proportional_q_07184000_01_20260814_local/"
        "C_s1/summary.json"
    ),
    "single_basin_propq_P_s0_summary": Path(
        "results/23_camels_switch_confirmation/"
        "camels_parfc_slz_state_proportional_q_07184000_01_20260814_local/"
        "P_s0/summary.json"
    ),
    "single_basin_propq_P_s1_summary": Path(
        "results/23_camels_switch_confirmation/"
        "camels_parfc_slz_state_proportional_q_07184000_01_20260814_local/"
        "P_s1/summary.json"
    ),
}
DECISION_GATES = {
    "task_count": 360,
    "source_task_count": 180,
    "events_per_arm": 1080,
    "events_per_transition_type_per_arm": 180,
    "primary_response_window_days": 30,
    "secondary_response_window_days": 90,
    "per_transition_type_event_pass_rate_min": 0.5,
    "zero_true_probability_days_max": 0,
    "severe_negative_log_probability_days_max": 0,
    "mean_true_negative_log_probability_max": 1.0986122886681098,
    "multiclass_brier_max": 0.6666666666666666,
    "secondary_tier_registered_before_execution": True,
}
INHERITED_INPUT_HASH_KEYS = (
    "parameter_table_sha256",
    "g1_precheck_table_sha256",
    "raw_input_manifest_sha256",
    "task_table_sha256",
    "initial_moment_manifest_sha256",
)


def _verify_filter_and_arms(config: Mapping) -> None:
    filter_config = config.get("filter")
    if not isinstance(filter_config, Mapping) or any(
        filter_config.get(key) != expected
        for key, expected in EXPECTED_FILTER.items()
    ):
        raise ValueError("proportional-Q filter contract changed")
    arms = config.get("arms")
    if not isinstance(arms, list) or tuple(arms) != base.EXPECTED_ARMS:
        raise ValueError("fixed arms contract changed")


def _verify_authorization_boundary(config: Mapping) -> None:
    boundary = config.get("authorization_boundary")
    if not isinstance(boundary, Mapping):
        raise ValueError("authorization_boundary must be a mapping")
    expected = {
        "design_seeds": [0, 1],
        "reserved_validation_seeds_authorized": False,
        "full_531_basin_run_authorized": False,
        "configuration_freeze_version_02_authorized": False,
        "ninety_basin_execution_authorized_by_user_go": True,
        "user_go_date": "2026-08-14",
    }
    for name, value in expected.items():
        if boundary.get(name) != value:
            raise ValueError(f"authorization boundary changed for {name}")


def _verify_motivating_evidence(root: Path, config: Mapping) -> dict[str, str]:
    evidence = config.get("motivating_evidence")
    if not isinstance(evidence, Mapping) or set(evidence) != set(MOTIVATING_EVIDENCE):
        raise ValueError("motivating evidence roles changed")
    hashes: dict[str, str] = {}
    for role, entry in evidence.items():
        if not isinstance(entry, Mapping):
            raise ValueError("motivating evidence entries must be mappings")
        path = base._registered_file(root, entry.get("path"), f"evidence file {role}")
        hashes[role] = base._verify_file_hash(
            path,
            entry.get("sha256"),
            f"evidence file {role}",
        )
    return hashes


def _verify_inherited_inputs(root: Path, config: Mapping) -> None:
    """The frozen 03B input identity must carry over unchanged by hash."""
    source_path = root / SOURCE_03B_CONFIGURATION
    observed = base.sha256_file(source_path)
    if observed != EXPECTED_03B_CONFIG_SHA256:
        raise ValueError("frozen 03B configuration hash changed")
    source = json.loads(source_path.read_text(encoding="utf-8"))
    inputs = config.get("inputs")
    source_inputs = source.get("inputs")
    if not isinstance(inputs, Mapping) or not isinstance(source_inputs, Mapping):
        raise ValueError("inputs must be mappings")
    for key in INHERITED_INPUT_HASH_KEYS:
        if inputs.get(key) != source_inputs.get(key):
            raise ValueError(f"inherited input hash changed for {key}")
    selection = config.get("design_selection")
    source_selection = source.get("design_selection")
    if not isinstance(selection, Mapping) or not isinstance(source_selection, Mapping):
        raise ValueError("design_selection must be a mapping")
    if selection.get("basin_list_sha256") != source_selection.get("basin_list_sha256"):
        raise ValueError("inherited basin list hash changed")


def verify_parameter_path_design90_propq(
    repo_root: str | Path,
    config_path: str | Path,
    expected_config_sha256: str,
    require_output_absent: bool = True,
) -> base.VerifiedMechanismRun:
    """Verify the frozen 03C configuration without creating its output.

    ``require_output_absent=False`` is for post-execution summarization: the
    same isolation checks run, but the registered output root must already
    exist instead of being absent.
    """
    root = Path(repo_root).resolve()
    configuration = Path(config_path)
    if not configuration.is_absolute():
        configuration = root / configuration
    configuration = configuration.resolve()
    if not configuration.is_file():
        raise FileNotFoundError(f"configuration is missing: {configuration}")
    try:
        configuration.relative_to(root)
    except ValueError as error:
        raise ValueError("configuration path must be inside the repository root") from error
    observed_config_hash = base.sha256_file(configuration)
    if observed_config_hash != str(expected_config_sha256):
        raise ValueError(
            "configuration SHA-256 changed: "
            f"expected {expected_config_sha256}, observed {observed_config_hash}"
        )
    config = json.loads(configuration.read_text(encoding="utf-8"))
    if not isinstance(config, Mapping):
        raise ValueError("configuration root must be a JSON object")
    if config.get("configuration_status") != CONFIGURATION_STATUS:
        raise ValueError(f"configuration_status must be {CONFIGURATION_STATUS}")
    if config.get("experiment_id") != EXPERIMENT_ID:
        raise ValueError("03C experiment_id changed")
    if config.get("decision_gates") != DECISION_GATES:
        raise ValueError("registered 03C decision gates changed")
    _verify_authorization_boundary(config)
    runtime_contract = base._verify_runtime_contract(config)
    _verify_filter_and_arms(config)
    if "design90_propq_runner" not in config.get("implementation", {}):
        raise ValueError("implementation mapping lacks design90_propq_runner")
    if require_output_absent:
        implementation_hashes = design._verify_implementation(root, config)
    else:
        # Post-execution summarization: the runner file itself gained its
        # summary-mode plumbing after the run, so it is the one declared
        # exception; every numerical-path file must still match, and the
        # drift is recorded, never hidden.
        implementation_hashes = {}
        for role, entry in config["implementation"].items():
            path = base._registered_file(
                root, entry.get("path"), f"implementation file {role}"
            )
            observed = base.sha256_file(path)
            if observed != str(entry.get("sha256")):
                if role != "design90_propq_runner":
                    raise ValueError(
                        f"implementation file SHA-256 changed for {role}: "
                        f"expected {entry.get('sha256')}, observed {observed}"
                    )
                implementation_hashes[f"{role}_registered"] = str(entry.get("sha256"))
                implementation_hashes[f"{role}_post_execution_amended"] = observed
            else:
                implementation_hashes[role] = observed
    evidence_hashes = _verify_motivating_evidence(root, config)
    _verify_inherited_inputs(root, config)
    inputs = config.get("inputs")
    outputs = config.get("outputs")
    if not isinstance(inputs, Mapping) or not isinstance(outputs, Mapping):
        raise ValueError("inputs and outputs must be mappings")
    basin_ids, _, basin_list_hash = design._load_basin_list(root, config)
    tasks, task_path, task_hash = design._verify_tasks(root, inputs, basin_ids)
    _, initial_manifest_hash, initial_manifest_rows = (
        base._verify_initial_moment_manifest(root, inputs, tasks)
    )
    parameter_path = base._registered_file(
        root, inputs.get("parameter_table"), "parameter table"
    )
    parameter_hash = base._verify_file_hash(
        parameter_path,
        inputs.get("parameter_table_sha256"),
        "parameter table",
    )
    g1_path = base._registered_file(root, inputs.get("g1_precheck_table"), "G1 table")
    g1_hash = base._verify_file_hash(
        g1_path,
        inputs.get("g1_precheck_table_sha256"),
        "G1 table",
    )
    raw_manifest_hash, raw_manifest_rows = base._verify_raw_input_manifest(root, inputs)
    data_root = base._relative_path(root, inputs.get("data_root"), "data root").resolve()
    if not data_root.is_dir():
        raise FileNotFoundError(f"data root directory is missing: {data_root}")
    parameter_rows = base._load_parameter_rows(root, inputs, basin_ids)
    if require_output_absent:
        output_root = base._verify_output_root(root, outputs, tasks)
    else:
        output_root = base._relative_path(
            root, outputs.get("root"), "output root"
        ).resolve()
        if not output_root.is_dir():
            raise FileNotFoundError(f"completed output root is missing: {output_root}")
    frozen_03b_root = (
        root / "results" / "23_camels_switch_confirmation"
        / "camels_parfc_transition_path_03b_design90_s01_20260811_local"
    ).resolve()
    if output_root == frozen_03b_root or base._is_within(output_root, frozen_03b_root):
        raise ValueError("03C output must not enter the frozen 03B result root")
    return base.VerifiedMechanismRun(
        configuration=json.loads(json.dumps(config)),
        config_path=configuration,
        config_sha256=observed_config_hash,
        task_table=tasks,
        task_table_path=task_path,
        task_table_sha256=task_hash,
        parameter_rows=parameter_rows,
        data_root=data_root,
        output_root=output_root,
        implementation_hashes=implementation_hashes,
        input_hashes={
            "parameter_table_sha256": parameter_hash,
            "g1_precheck_table_sha256": g1_hash,
            "raw_input_manifest_sha256": raw_manifest_hash,
            "raw_input_manifest_rows": raw_manifest_rows,
            "initial_moment_manifest_sha256": initial_manifest_hash,
            "initial_moment_manifest_rows": initial_manifest_rows,
            "basin_list_sha256": basin_list_hash,
            **{f"evidence_{role}": value for role, value in evidence_hashes.items()},
        },
        runtime_contract=runtime_contract,
    )


def run_parameter_path_design90_propq(
    config_path: str | Path,
    expected_config_sha256: str,
    workers: int,
) -> dict:
    if isinstance(workers, bool) or not isinstance(workers, int) or workers <= 0:
        raise ValueError("workers must be a positive integer")
    verified = verify_parameter_path_design90_propq(
        _REPO_ROOT,
        config_path,
        expected_config_sha256,
    )
    work = design._build_work(verified)
    if len(work) != design.PLANNED_TASK_COUNT:
        raise RuntimeError("internal work construction must produce exactly 360 tasks")
    if any(item[6] != EXPECTED_FILTER["q_mode"] for item in work):
        raise RuntimeError("every 03C work item must use the proportional Q mode")
    verified.output_root.mkdir(parents=True, exist_ok=False)
    arms_root = verified.output_root / "arms"
    arms_root.mkdir(exist_ok=False)
    for arm_id in ("C", "P"):
        arm_root = arms_root / arm_id
        arm_root.mkdir(exist_ok=False)
        (arm_root / "probs").mkdir(exist_ok=False)
    execution = execute_fail_fast(
        work=work,
        worker=_run_one,
        task_key=lambda item: {
            "basin_id": item[0],
            "seed": item[1],
            "arm_id": item[-1],
        },
        max_workers=workers,
    )
    return design._write_outputs(verified, execution)


def _implementation_entries() -> dict:
    source = json.loads(
        (_REPO_ROOT / SOURCE_03B_CONFIGURATION).read_text(encoding="utf-8")
    )
    entries = {}
    for role, entry in source["implementation"].items():
        path = Path(entry["path"])
        if role == "preregistration":
            path = PREREGISTRATION
        entries[role] = {
            "path": path.as_posix(),
            "sha256": base.sha256_file(_REPO_ROOT / path),
        }
    entries["design90_propq_runner"] = {
        "path": "src/camels_switch_confirmation/run_parameter_path_design90_propq.py",
        "sha256": base.sha256_file(Path(__file__)),
    }
    return entries


def prepare_configuration() -> dict:
    """Write the frozen 03C configuration; never runs the experiment."""
    configuration_path = _REPO_ROOT / CONFIGURATION
    if configuration_path.exists():
        raise FileExistsError(f"configuration already exists: {configuration_path}")
    if (_REPO_ROOT / OUTPUT_ROOT).exists():
        raise FileExistsError(f"registered output root already exists: {OUTPUT_ROOT}")
    if not (_REPO_ROOT / PREREGISTRATION).is_file():
        raise FileNotFoundError("03C preregistration document is missing")
    source_path = _REPO_ROOT / SOURCE_03B_CONFIGURATION
    if base.sha256_file(source_path) != EXPECTED_03B_CONFIG_SHA256:
        raise ValueError("frozen 03B configuration hash changed")
    source = json.loads(source_path.read_text(encoding="utf-8"))
    for key in INHERITED_INPUT_HASH_KEYS:
        name = key.removesuffix("_sha256")
        live = base.sha256_file(_REPO_ROOT / source["inputs"][name])
        if live != source["inputs"][key]:
            raise ValueError(f"inherited frozen input changed on disk: {name}")
    evidence = {
        role: {
            "path": path.as_posix(),
            "sha256": base.sha256_file(_REPO_ROOT / path),
        }
        for role, path in MOTIVATING_EVIDENCE.items()
    }
    config = {
        "experiment_id": EXPERIMENT_ID,
        "configuration_status": CONFIGURATION_STATUS,
        "registered_date": "2026-08-14",
        "changed_factor_against_03b": {
            "filter_q_mode": "fixed -> lower_groundwater_state_proportional",
            "everything_else": "inherited_from_frozen_03b_by_hash_equality",
        },
        "authorization_boundary": {
            "design_seeds": [0, 1],
            "reserved_validation_seeds_authorized": False,
            "full_531_basin_run_authorized": False,
            "configuration_freeze_version_02_authorized": False,
            "ninety_basin_execution_authorized_by_user_go": True,
            "user_go_date": "2026-08-14",
        },
        "source_03b_configuration": {
            "path": SOURCE_03B_CONFIGURATION.as_posix(),
            "sha256": EXPECTED_03B_CONFIG_SHA256,
        },
        "motivating_evidence": evidence,
        "inputs": dict(source["inputs"]),
        "design_selection": dict(source["design_selection"]),
        "initial_moment_contract": dict(source["initial_moment_contract"]),
        "filter": dict(EXPECTED_FILTER),
        "arms": [dict(value) for value in source["arms"]],
        "implementation": _implementation_entries(),
        "runtime": base._observed_runtime_contract(),
        "outputs": {"root": OUTPUT_ROOT.as_posix()},
        "decision_gates": dict(DECISION_GATES),
        "claim_boundary": {
            "parameter_candidate_identification": "exploratory_design90_only",
            "noise_candidate_identification": "not_tested",
            "complete_state_accuracy": "not_tested",
            "forecast_value": "not_tested",
            "real_observation_assimilation_value": "not_tested",
            "truth_noise_magnitude_known_a_priori": True,
        },
    }
    with configuration_path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(config, handle, indent=2, sort_keys=False)
        handle.write("\n")
    config_hash = base.sha256_file(configuration_path)
    verified = verify_parameter_path_design90_propq(
        _REPO_ROOT,
        configuration_path,
        config_hash,
    )
    if len(verified.task_table) != 180 or verified.output_root.exists():
        raise ValueError("03C read-only preflight did not pass")
    return {
        "status": "configuration_prepared_not_run",
        "configuration_path": CONFIGURATION.as_posix(),
        "configuration_sha256": config_hash,
        "planned_tasks": 360,
    }


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "run"))
    parser.add_argument("--config", default=str(CONFIGURATION))
    parser.add_argument("--expected-config-sha256")
    parser.add_argument("--workers", type=int, default=4)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    try:
        if arguments.mode == "prepare":
            result = prepare_configuration()
        else:
            if not arguments.expected_config_sha256:
                raise ValueError("run mode requires --expected-config-sha256")
            result = run_parameter_path_design90_propq(
                arguments.config,
                arguments.expected_config_sha256,
                arguments.workers,
            )
    except Exception as error:  # noqa: BLE001 - executable must stop cleanly
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
