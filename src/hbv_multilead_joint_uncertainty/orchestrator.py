"""Two-stage serial orchestration for contract preparation and frozen evaluation."""

from __future__ import annotations

import json
import os
import gc
import platform
import sys
from importlib import metadata
from pathlib import Path
from typing import Mapping

import pandas as pd
import numpy as np
import psutil

from hbv_joint_uncertainty.candidates import sha256_file
from hbv_joint_uncertainty.hbv_adapter import simulate_adapter

from .basins import freeze_formal_selection
from .contracts import csv_projection_sha256, load_base_config
from .experiment import (
    BasinEvaluation,
    ResultPackageWriter,
    verify_contract_package,
    verify_result_package,
    write_contract_package,
)
from .input_audit import (
    audit_basin_inputs,
    audit_evaluation_discharge,
    load_frozen_calibration_discharge,
)
from .preparation import (
    _load_complete_period,
    _load_forcing_only_period,
    _method_contract_parts,
    evaluate_development_interaction_modes,
    prepare_basin_uncertainty_contract,
)
from .resource_monitor import (
    RUN_RESOURCE_ESTIMATES_GIB,
    ResourceRecorder,
    verify_resource_history_rows,
)
from .registry import RunRegistry
from .runner import run_five_methods


def _one_match(root: Path, pattern: str) -> Path:
    matches = list(root.rglob(pattern))
    if len(matches) != 1:
        raise ValueError(f"expected one file matching {pattern}, found {len(matches)}")
    return matches[0].resolve()


def _verify_recomputed_formal_table(saved: pd.DataFrame, recomputed: pd.DataFrame) -> None:
    required = ("gauge_id", "climate_stratum", "response_stratum", "area_stratum", "huc_02")
    if len(saved) != 16 or len(recomputed) != 16:
        raise ValueError("formal selection must contain exactly sixteen basins")
    for column in required:
        if column not in saved or column not in recomputed:
            raise ValueError(f"formal selection lacks required column {column}")
        actual = saved[column].astype(str)
        expected = recomputed[column].astype(str)
        if column == "gauge_id":
            actual = actual.str.zfill(8)
            expected = expected.str.zfill(8)
        elif column == "huc_02":
            actual = actual.str.zfill(2)
            expected = expected.str.zfill(2)
        if actual.tolist() != expected.tolist():
            raise ValueError(
                f"formal selection differs from monitored static-rule recomputation: {column}"
            )


def collect_contract_snapshot_files(
    repo_root: Path,
    basin_ids: list[str],
    config: Mapping,
    include_evaluation_discharge: bool = False,
) -> tuple[list[Path], list[Path]]:
    root = Path(repo_root).resolve()
    idea_root = root / "src" / "hbv_multilead_joint_uncertainty"
    source_files = [
        path
        for path in idea_root.rglob("*")
        if path.is_file() and "__pycache__" not in path.parts and path.suffix in {".py", ".md"}
    ]
    source_files.extend(sorted((root / "test").glob("test_hbv_multilead_*.py")))
    source_files.extend(
        [
            root / "src" / "hbv_joint_uncertainty" / "__init__.py",
            root / "src" / "hbv_joint_uncertainty" / "hbv_adapter.py",
            root / "src" / "hbv_joint_uncertainty" / "candidates.py",
            root / "src" / "hbv_joint_uncertainty" / "sigma_filter.py",
            root / "src" / "hbv_joint_uncertainty" / "preflight.py",
            root / "src" / "hbv_joint_uncertainty" / "imm.py",
            root / "src" / "hbv_joint_uncertainty" / "resource_monitor.py",
        ]
    )
    data_root = Path(config["data_root"])
    if not data_root.is_absolute():
        data_root = root / data_root
    input_files = []
    for basin_id in basin_ids:
        input_files.extend(
            [
                _one_match(
                    data_root / "basin_mean_forcing" / "maurer",
                    f"{basin_id}_lump_maurer_forcing_leap.txt",
                ),
                _one_match(
                    data_root / "basin_mean_forcing" / "daymet",
                    f"{basin_id}_lump_cida_forcing_leap.txt",
                ),
            ]
        )
        if include_evaluation_discharge:
            input_files.append(
                _one_match(data_root / "usgs_streamflow", f"{basin_id}_streamflow_qc.txt")
            )
    input_files.extend(
        [
            *(data_root / "camels_attributes_v2.0" / name for name in (
                "camels_clim.txt",
                "camels_topo.txt",
                "camels_soil.txt",
                "camels_vege.txt",
                "camels_name.txt",
            )),
            root / config["parameter_source"]["metadata_path"],
            root / config["parameter_source"]["table_path"],
            root / config["calibration_discharge_source"]["table_path"],
            root / config["calibration_discharge_source"]["metadata_path"],
            root
            / config.get(
                "_loaded_config_path",
                "src/hbv_multilead_joint_uncertainty/configs/base_v01.json",
            ),
            root / config["pilot_basin_file"],
            root / config["formal_basin_file"],
            root / "src" / "xaj_global_pilot" / "configs" / "conceptual_benchmark_camels_us_531_repro.txt",
            root / "src" / "xaj_global_pilot" / "configs" / "conceptual_benchmark_15_basins.csv",
        ]
    )
    return sorted(set(path.resolve() for path in source_files)), sorted(
        set(path.resolve() for path in input_files)
    )


def _environment_versions() -> dict:
    packages = {}
    for package in (
        "numpy",
        "scipy",
        "pandas",
        "numba",
        "psutil",
        "matplotlib",
        "Pillow",
        "threadpoolctl",
    ):
        try:
            packages[package] = metadata.version(package)
        except metadata.PackageNotFoundError:
            packages[package] = None
    return {
        "python": sys.version,
        "platform": platform.platform(),
        "packages": packages,
        "process": {
            "process_id": os.getpid(),
            "create_time_unix_seconds": psutil.Process().create_time(),
            "executable": sys.executable,
            "arguments": list(sys.argv),
        },
    }


def _execution_signature(
    repo_root: Path,
    basin_ids: list[str],
    config: Mapping,
    source_files: list[Path],
    input_files: list[Path],
    include_calibration_discharge: bool,
) -> dict:
    root = Path(repo_root).resolve()
    process_create_time = psutil.Process().create_time()
    latest_source_mtime = max((path.stat().st_mtime for path in source_files), default=0.0)
    if latest_source_mtime > process_create_time + 2.0:
        raise RuntimeError(
            "a source file changed after this Python process started; rerun in a new process"
        )
    file_hashes = {
        path.relative_to(root).as_posix(): sha256_file(path)
        for path in sorted({Path(value).resolve() for value in [*source_files, *input_files]})
    }
    signature = {
        "files_sha256": file_hashes,
        "environment": _environment_versions(),
        "source_process_freshness": {
            "process_create_time_unix_seconds": process_create_time,
            "latest_source_mtime_unix_seconds": latest_source_mtime,
            "maximum_clock_tolerance_seconds": 2.0,
            "passed": True,
        },
    }
    if include_calibration_discharge:
        parameter_path = root / config["parameter_source"]["table_path"]
        signature["parameter_table_sha256"] = sha256_file(parameter_path)
        signature["parameter_projection_content_sha256"] = csv_projection_sha256(parameter_path)
        discharge_hashes = {}
        for basin_id in basin_ids:
            _, _, provenance = load_frozen_calibration_discharge(
                root,
                basin_id,
                dict(config),
            )
            discharge_hashes[basin_id] = provenance["raw_source"]["selected_source_lines_sha256"]
        signature["calibration_discharge_slice_sha256"] = discharge_hashes
    return signature


def _verified_execution_signature(start: Mapping, end: Mapping) -> dict:
    if dict(start) != dict(end):
        raise RuntimeError("source, input, or environment changed during the run")
    return {**dict(start), "verified_unchanged_from_start_to_finish": True}


def _quarantine_published_artifact(
    output: Path,
    failed_output: Path,
    error: Exception,
) -> Path | None:
    published = Path(output).resolve()
    failed = Path(failed_output).resolve()
    if not published.exists():
        return None
    if failed.exists():
        raise FileExistsError(f"failed artifact path already exists: {failed}")
    rename_error = None
    try:
        os.replace(published, failed)
        target = failed
    except Exception as current_error:
        rename_error = current_error
        target = published
    marker = {
        "status": "failed_after_publish",
        "error_type": type(error).__name__,
        "message": str(error),
        "rename_error": (
            None if rename_error is None else f"{type(rename_error).__name__}: {rename_error}"
        ),
    }
    try:
        (target / "failure.json").write_text(
            json.dumps(marker, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except Exception as marker_error:
        if rename_error is not None:
            raise RuntimeError(
                "published artifact could neither be renamed nor marked as failed"
            ) from marker_error
    return target


def verify_run_log(log_directory: Path) -> dict:
    directory = Path(log_directory).resolve()
    summary = json.loads((directory / "run_summary.json").read_text(encoding="utf-8"))
    if summary.get("status") != "verified":
        raise ValueError("run log does not describe a verified run")
    resource_path = directory / "resource_history.json"
    if sha256_file(resource_path) != summary.get("resource_history_sha256"):
        raise ValueError("run resource-history checksum does not match the summary")
    history = json.loads(resource_path.read_text(encoding="utf-8"))
    artifact = Path(summary["output_directory"]).resolve()
    config = json.loads((artifact / "config_snapshot.json").read_text(encoding="utf-8"))
    if (artifact / "contract_manifest.json").is_file():
        run_kind = "contract"
    elif (artifact / "result_manifest.json").is_file():
        run_kind = "evaluation"
    else:
        raise ValueError("run log output is not a recognized contract or result package")
    resource_verification = verify_resource_history_rows(
        history,
        config["resource"],
        require_finish=True,
        run_kind=run_kind,
    )
    if (
        summary.get("resource_sample_count") != len(history)
        or summary.get("resource_last_event") != "finish"
        or summary.get("resource_monitor_covers_packaging_and_verification") is not True
    ):
        raise ValueError("run summary does not bind the complete monitored tail")
    saved_verification = json.loads((directory / "verification.json").read_text(encoding="utf-8"))
    if run_kind == "contract":
        required_post_verification_event = "after_contract_verification"
        fresh_verification = verify_contract_package(artifact)
    else:
        required_post_verification_event = "after_result_verification"
        fresh_verification = verify_result_package(artifact)
    events = [str(row.get("event")) for row in history]
    if required_post_verification_event not in events[:-1]:
        raise ValueError("resource history lacks the required post-verification sample")
    if saved_verification != fresh_verification:
        raise ValueError("saved and fresh artifact verification results differ")
    return {
        "status": "verified",
        "log_directory": str(directory),
        "output_directory": str(artifact),
        "resource_sample_count": resource_verification["sample_count"],
        "maximum_resource_gap_seconds": resource_verification["maximum_gap_seconds"],
        "artifact_verification": fresh_verification,
    }


def prepare_contract_package(
    repo_root: Path,
    contract_id: str,
    basin_table: pd.DataFrame,
    config_path: Path | None = None,
    interaction_audit: Mapping | None = None,
    prerequisite_contract: Path | None = None,
    prerequisite_basin_ids: list[str] | None = None,
) -> dict:
    root = Path(repo_root).resolve()
    config = load_base_config(root, config_path=config_path)
    table = basin_table.copy()
    table["gauge_id"] = table["gauge_id"].astype(str).str.zfill(8)
    basin_ids = table["gauge_id"].tolist()
    if not basin_ids or len(basin_ids) != len(set(basin_ids)):
        raise ValueError("basin_table must contain unique basins")
    results_root = root / config["results_root"]
    logs_root = root / config["logs_root"]
    output = results_root / contract_id
    log_output = logs_root / contract_id
    temporary_log = logs_root / f".{contract_id}.incomplete"
    failed_log = logs_root / f"{contract_id}.failed"
    failed_output = results_root / f"{contract_id}.failed"
    if any(path.exists() for path in (output, log_output, temporary_log, failed_log, failed_output)):
        raise FileExistsError(f"refusing to overwrite contract or log path for {contract_id}")
    registry = RunRegistry(results_root, contract_id)
    registry.reserve("calibration_contract", basin_count=len(basin_ids))
    recorder = None
    contracts = {}
    audits = {}
    try:
        temporary_log.mkdir(parents=True)
        resource_probe = results_root
        while not resource_probe.exists() and resource_probe != resource_probe.parent:
            resource_probe = resource_probe.parent
        recorder = ResourceRecorder(
            probe_path=resource_probe,
            resource_config=config["resource"],
            history_path=temporary_log / "resource_history.json",
        )
        recorder.start(**RUN_RESOURCE_ESTIMATES_GIB["contract"], contract_id=contract_id)
        source_files, input_files = collect_contract_snapshot_files(root, basin_ids, config)
        start_signature = _execution_signature(
            root,
            basin_ids,
            config,
            source_files,
            input_files,
            include_calibration_discharge=True,
        )
        (temporary_log / "execution_signature_start.json").write_text(
            json.dumps(start_signature, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        if prerequisite_contract is not None:
            if prerequisite_basin_ids is None or interaction_audit is None:
                raise ValueError(
                    "a prerequisite contract requires expected basin identifiers and interaction audit"
                )
            prerequisite = Path(prerequisite_contract).resolve()
            expected_prerequisite_ids = [
                str(value).strip().zfill(8) for value in prerequisite_basin_ids
            ]
            recorder.checkpoint(
                "before_prerequisite_contract_verification",
                force=True,
                prerequisite_contract=str(prerequisite),
            )
            prerequisite_verification = verify_contract_package(prerequisite)
            verified_prerequisite_table = pd.read_csv(
                prerequisite / "basins.csv", dtype={"gauge_id": str}
            )
            verified_prerequisite_ids = (
                verified_prerequisite_table["gauge_id"].str.zfill(8).tolist()
            )
            if verified_prerequisite_ids != expected_prerequisite_ids:
                raise ValueError(
                    "prerequisite contract basins differ from the identifiers used for formal selection"
                )
            verified_interaction = json.loads(
                (prerequisite / "interaction_audit.json").read_text(encoding="utf-8")
            )
            if verified_interaction != dict(interaction_audit):
                raise ValueError(
                    "prerequisite interaction audit differs from the audit supplied for formal preparation"
                )
            if (
                verified_interaction.get("selected_mode") != "full"
                or prerequisite_verification.get("interaction_mode") != "full"
            ):
                raise ValueError("formal preparation requires a full interaction prerequisite")
            frozen_pilot_table = pd.read_csv(
                root / config["pilot_basin_file"], dtype={"basin_id": str}
            )
            frozen_pilot_ids = frozen_pilot_table["basin_id"].str.zfill(8).tolist()
            if (
                len(frozen_pilot_ids) != 6
                or len(set(frozen_pilot_ids)) != 6
                or verified_prerequisite_ids != frozen_pilot_ids
            ):
                raise ValueError(
                    "prerequisite contract must contain the frozen six development basins in order"
                )
            prerequisite_config = json.loads(
                (prerequisite / "config_snapshot.json").read_text(encoding="utf-8")
            )
            expected_selection_schema = config.get("parameter_selection", {}).get(
                "schema_version"
            )
            if expected_selection_schema not in (2, 3):
                raise ValueError("formal preparation parameter selection schema is unsupported")
            if (
                prerequisite_config.get("parameter_selection", {}).get("schema_version")
                != expected_selection_schema
            ):
                raise ValueError(
                    "formal preparation requires the prerequisite parameter selection schema "
                    "to match the active frozen config"
                )
            required_parameter_ids = {
                "equifinal_diverse_1",
                "trained_center",
                "equifinal_diverse_2",
            }
            for frozen_basin_id in frozen_pilot_ids:
                frozen_contract = json.loads(
                    (prerequisite / "basin_contracts" / f"{frozen_basin_id}.json").read_text(
                        encoding="utf-8"
                    )
                )
                if (
                    frozen_contract.get("parameter_selection", {}).get("schema_version")
                    != expected_selection_schema
                    or set(frozen_contract.get("parameter_vectors", {})) != required_parameter_ids
                ):
                    raise ValueError(
                        "formal preparation requires current parameter selection contracts"
                    )
            expected_prerequisite = config.get("formal_prerequisite_contract", {})
            prerequisite_checksums_sha256 = sha256_file(prerequisite / "checksums.json")
            if (
                prerequisite_verification.get("contract_id")
                != expected_prerequisite.get("contract_id")
                or prerequisite_checksums_sha256
                != expected_prerequisite.get("checksums_sha256")
            ):
                raise ValueError(
                    "prerequisite contract identity or checksum differs from the frozen reviewed contract"
                )
            try:
                prerequisite_path = prerequisite.relative_to(root).as_posix()
            except ValueError:
                prerequisite_path = str(prerequisite)
            config["prerequisite_contract"] = {
                "path": prerequisite_path,
                "contract_id": prerequisite_verification["contract_id"],
                "checksums_sha256": prerequisite_checksums_sha256,
                "basins": verified_prerequisite_ids,
                "selected_interaction_mode": verified_interaction["selected_mode"],
            }
            recorder.checkpoint(
                "after_prerequisite_contract_verification",
                force=True,
                prerequisite_contract_id=prerequisite_verification["contract_id"],
            )
            recorder.checkpoint(
                "before_formal_selection_recomputation",
                force=True,
                prerequisite_contract_id=prerequisite_verification["contract_id"],
            )
            recomputed_formal_table = freeze_formal_selection(
                root, additional_development_ids=frozen_pilot_ids
            )
            _verify_recomputed_formal_table(table, recomputed_formal_table)
            recorder.checkpoint(
                "after_formal_selection_recomputation",
                force=True,
                formal_basin_count=len(recomputed_formal_table),
            )
        for basin_index, basin_id in enumerate(basin_ids):
            audit = audit_basin_inputs(root, basin_id, config)
            if not audit["passed"]:
                raise ValueError(f"basin {basin_id} failed input checks: {audit['failed_checks']}")
            audits[basin_id] = audit

            def progress(stage: str, completed: int, total: int, current=basin_id) -> None:
                recorder.checkpoint(
                    "contract_preparation",
                    basin_id=current,
                    stage=stage,
                    completed=completed,
                    total=total,
                )

            contracts[basin_id] = prepare_basin_uncertainty_contract(
                root,
                basin_id,
                config,
                progress_callback=progress,
            )
            recorder.checkpoint(
                "basin_contract_complete",
                force=True,
                basin_id=basin_id,
                basin_index=basin_index + 1,
                basin_count=len(basin_ids),
            )
        if interaction_audit is None:
            interaction_result = evaluate_development_interaction_modes(
                root,
                contracts,
                config,
                progress_callback=lambda stage, completed, total: recorder.checkpoint(
                    "interaction_mode_audit",
                    stage=stage,
                    completed=completed,
                    total=total,
                ),
            )
        else:
            interaction_result = dict(interaction_audit)
            if interaction_result.get("uses_evaluation_discharge") is not False:
                raise ValueError("supplied interaction audit must exclude evaluation discharge")
        config["formal_interaction_mode"] = interaction_result["selected_mode"]
        end_signature = _execution_signature(
            root,
            basin_ids,
            config,
            source_files,
            input_files,
            include_calibration_discharge=True,
        )
        execution_signature = _verified_execution_signature(start_signature, end_signature)
        recorder.checkpoint("before_contract_write", force=True, contract_id=contract_id)
        package = write_contract_package(
            results_root=results_root,
            contract_id=contract_id,
            config=config,
            basin_table=table,
            basin_contracts=contracts,
            input_audits=audits,
            resource_history=recorder.history,
            interaction_audit=interaction_result,
            source_files=source_files,
            input_files=input_files,
            repo_root=root,
            execution_signature=execution_signature,
        )
        verification = verify_contract_package(package)
        (temporary_log / "verification.json").write_text(
            json.dumps(verification, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        recorder.checkpoint("after_contract_verification", force=True, contract_id=contract_id)
        recorder.finish(contract_id=contract_id)
        resource_path = temporary_log / "resource_history.json"
        (temporary_log / "run_summary.json").write_text(
            json.dumps(
                {
                    "status": "verified",
                    "contract_id": contract_id,
                    "output_directory": str(package),
                    "basins": basin_ids,
                    "resource_sample_count": len(recorder.history),
                    "resource_last_event": recorder.history[-1]["event"],
                    "resource_history_sha256": sha256_file(resource_path),
                    "resource_monitor_covers_packaging_and_verification": True,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        os.replace(temporary_log, log_output)
        registry.update("verified", output_directory=str(package), log_directory=str(log_output))
        return {
            "status": "verified",
            "contract_id": contract_id,
            "output_directory": str(package),
            "log_directory": str(log_output),
            "basins": basin_ids,
            "verification": verification,
        }
    except Exception as error:
        abort_error = None
        quarantine_error = None
        if recorder is not None:
            try:
                recorder.abort()
            except Exception as cleanup_error:
                abort_error = cleanup_error
        try:
            _quarantine_published_artifact(output, failed_output, error)
        except Exception as cleanup_error:
            quarantine_error = cleanup_error
        if temporary_log.exists():
            (temporary_log / "failure.json").write_text(
                json.dumps(
                    {
                        "status": "failed",
                        "error_type": type(error).__name__,
                        "message": str(error),
                        "resource_monitor_cleanup_error": (
                            None if abort_error is None else f"{type(abort_error).__name__}: {abort_error}"
                        ),
                        "published_artifact_quarantine_error": (
                            None
                            if quarantine_error is None
                            else f"{type(quarantine_error).__name__}: {quarantine_error}"
                        ),
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            failed = logs_root / f"{contract_id}.failed"
            if abort_error is None and not failed.exists():
                os.replace(temporary_log, failed)
        try:
            registry.update("failed", error_type=type(error).__name__, message=str(error))
        except Exception:
            pass
        raise


def run_contract_evaluation(
    repo_root: Path,
    contract_directory: Path,
    experiment_id: str,
) -> dict:
    root = Path(repo_root).resolve()
    contract_path = Path(contract_directory).resolve()
    config = json.loads((contract_path / "config_snapshot.json").read_text(encoding="utf-8"))
    basin_table = pd.read_csv(contract_path / "basins.csv", dtype={"gauge_id": str})
    basin_ids = basin_table["gauge_id"].str.zfill(8).tolist()
    contract_manifest = json.loads(
        (contract_path / "contract_manifest.json").read_text(encoding="utf-8")
    )
    provisional_contract_id = contract_manifest.get("contract_id")
    if not isinstance(provisional_contract_id, str) or not provisional_contract_id:
        raise ValueError("contract manifest has no identifier")
    results_root = root / config["results_root"]
    logs_root = root / config["logs_root"]
    output = results_root / experiment_id
    log_output = logs_root / experiment_id
    temporary_log = logs_root / f".{experiment_id}.incomplete"
    failed_log = logs_root / f"{experiment_id}.failed"
    failed_output = results_root / f"{experiment_id}.failed"
    if any(path.exists() for path in (output, log_output, temporary_log, failed_log, failed_output)):
        raise FileExistsError(f"refusing to overwrite evaluation or log path for {experiment_id}")
    registry = RunRegistry(results_root, experiment_id)
    registry.reserve(
        "frozen_evaluation",
        basin_count=len(basin_ids),
        contract_id=provisional_contract_id,
    )
    recorder = None
    writer = None
    try:
        temporary_log.mkdir(parents=True)
        recorder = ResourceRecorder(
            probe_path=results_root,
            resource_config=config["resource"],
            history_path=temporary_log / "resource_history.json",
        )
        recorder.start(**RUN_RESOURCE_ESTIMATES_GIB["evaluation"], experiment_id=experiment_id)
        recorder.checkpoint(
            "before_contract_preflight_verification",
            force=True,
            contract_id=provisional_contract_id,
        )
        contract_verification = verify_contract_package(contract_path)
        if contract_verification["contract_id"] != provisional_contract_id:
            raise ValueError("verified contract identifier changed from its manifest")
        recorder.checkpoint(
            "after_contract_preflight_verification",
            force=True,
            contract_id=provisional_contract_id,
        )
        source_files, input_files = collect_contract_snapshot_files(
            root,
            basin_ids,
            config,
            include_evaluation_discharge=True,
        )
        start_signature = _execution_signature(
            root,
            basin_ids,
            config,
            source_files,
            input_files,
            include_calibration_discharge=False,
        )
        (temporary_log / "execution_signature_start.json").write_text(
            json.dumps(start_signature, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        writer = ResultPackageWriter(
            results_root=results_root,
            experiment_id=experiment_id,
            contract_directory=contract_path,
            config=config,
            verified_contract=contract_verification,
        )
        for basin_index, basin_id in enumerate(basin_ids):
            evaluation_audit = audit_evaluation_discharge(root, basin_id, contract_path)
            if not evaluation_audit["passed"]:
                raise ValueError(
                    f"basin {basin_id} failed evaluation input checks: {evaluation_audit['failed_checks']}"
                )
            basin_contract = json.loads(
                (contract_path / "basin_contracts" / f"{basin_id}.json").read_text(encoding="utf-8")
            )
            warmup = _load_forcing_only_period(
                root,
                basin_id,
                config,
                config["evaluation_warmup_start"],
                config["evaluation_warmup_end"],
            )
            evaluation, observations = _load_complete_period(
                root,
                basin_id,
                config,
                config["evaluation_start"],
                config["evaluation_end"],
            )
            if not np.all(np.isfinite(observations)):
                raise ValueError(f"basin {basin_id} has missing evaluation discharge")
            parameter_vectors, process_scales, process_covariances = _method_contract_parts(basin_contract)
            initial_states = {}
            for parameter_id, parameters in parameter_vectors.items():
                _, states = simulate_adapter(
                    warmup[:, 0], warmup[:, 1], warmup[:, 2], parameters
                )
                initial_states[parameter_id] = states[-1]
            center_state = initial_states["trained_center"]
            initial_covariance = np.diag(
                (float(config["initial_covariance_fraction"]) * np.maximum(np.abs(center_state), 1.0)) ** 2
            )
            methods = run_five_methods(
                forcing=evaluation,
                observations=observations,
                parameter_vectors=parameter_vectors,
                process_scales=process_scales,
                process_covariances=process_covariances,
                selected_process_id=basin_contract["process_noise"]["selected_process_id"],
                initial_states=initial_states,
                initial_covariance=initial_covariance,
                observation_standard_deviation=basin_contract["observation_noise"][
                    "selected_standard_deviation_mm_day"
                ],
                factor_transition_stay_probability=float(
                    config["factor_transition_stay_probability"]
                ),
                interaction_mode=config["formal_interaction_mode"],
                lead_days=tuple(config["lead_days"]),
                progress_callback=lambda method, completed, total, current=basin_id: recorder.checkpoint(
                    "evaluation_progress",
                    basin_id=current,
                    method=method,
                    completed=completed,
                    total=total,
                ),
            )
            dates = pd.date_range(config["evaluation_start"], config["evaluation_end"], freq="D")
            writer.write_basin(
                BasinEvaluation(
                    basin_id=basin_id,
                    dates=dates.strftime("%Y-%m-%d").to_numpy(),
                    observations=observations,
                    methods=methods,
                ),
                evaluation_input_audit=evaluation_audit,
            )
            del methods, initial_states, process_covariances, evaluation, observations
            gc.collect()
            recorder.checkpoint(
                "basin_evaluation_complete",
                force=True,
                basin_id=basin_id,
                basin_index=basin_index + 1,
                basin_count=len(basin_ids),
            )
        end_signature = _execution_signature(
            root,
            basin_ids,
            config,
            source_files,
            input_files,
            include_calibration_discharge=False,
        )
        execution_signature = _verified_execution_signature(start_signature, end_signature)
        recorder.checkpoint("before_result_write", force=True, experiment_id=experiment_id)
        package = writer.finalize(
            resource_history=recorder.history,
            source_files=source_files,
            repo_root=root,
            input_files=input_files,
            execution_signature=execution_signature,
        )
        verification = verify_result_package(package)
        (temporary_log / "verification.json").write_text(
            json.dumps(verification, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        recorder.checkpoint("after_result_verification", force=True, experiment_id=experiment_id)
        recorder.finish(experiment_id=experiment_id)
        resource_path = temporary_log / "resource_history.json"
        (temporary_log / "run_summary.json").write_text(
            json.dumps(
                {
                    "status": "verified",
                    "experiment_id": experiment_id,
                    "contract_id": contract_verification["contract_id"],
                    "output_directory": str(package),
                    "basins": basin_ids,
                    "resource_sample_count": len(recorder.history),
                    "resource_last_event": recorder.history[-1]["event"],
                    "resource_history_sha256": sha256_file(resource_path),
                    "resource_monitor_covers_packaging_and_verification": True,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        os.replace(temporary_log, log_output)
        registry.update("verified", output_directory=str(package), log_directory=str(log_output))
        return {
            "status": "verified",
            "experiment_id": experiment_id,
            "contract_id": contract_verification["contract_id"],
            "output_directory": str(package),
            "log_directory": str(log_output),
            "verification": verification,
        }
    except Exception as error:
        abort_error = None
        quarantine_error = None
        writer_failure_error = None
        if recorder is not None:
            try:
                recorder.abort()
            except Exception as cleanup_error:
                abort_error = cleanup_error
        try:
            _quarantine_published_artifact(output, failed_output, error)
        except Exception as cleanup_error:
            quarantine_error = cleanup_error
        if writer is not None:
            try:
                writer.preserve_failure(error)
            except Exception as cleanup_error:
                writer_failure_error = cleanup_error
        if temporary_log.exists():
            (temporary_log / "failure.json").write_text(
                json.dumps(
                    {
                        "status": "failed",
                        "error_type": type(error).__name__,
                        "message": str(error),
                        "resource_monitor_cleanup_error": (
                            None if abort_error is None else f"{type(abort_error).__name__}: {abort_error}"
                        ),
                        "published_artifact_quarantine_error": (
                            None
                            if quarantine_error is None
                            else f"{type(quarantine_error).__name__}: {quarantine_error}"
                        ),
                        "incomplete_result_preservation_error": (
                            None
                            if writer_failure_error is None
                            else f"{type(writer_failure_error).__name__}: {writer_failure_error}"
                        ),
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            failed = logs_root / f"{experiment_id}.failed"
            if abort_error is None and not failed.exists():
                os.replace(temporary_log, failed)
        try:
            registry.update("failed", error_type=type(error).__name__, message=str(error))
        except Exception:
            pass
        raise
