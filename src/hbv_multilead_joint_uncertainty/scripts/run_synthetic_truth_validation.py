"""Save independently replayable evidence for deterministic HBV-lite truth propagation."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.metadata
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import simulate_adapter  # noqa: E402
from hbv_multilead_joint_uncertainty.synthetic_truth import generate_reference_truth  # noqa: E402


REQUIRED_EVIDENCE_FILES = frozenset(
    {
        "conda_packages.json",
        "config_snapshot.json",
        "environment.json",
        "evidence.npz",
        "git_status.txt",
        "installed_packages.json",
        "pip_freeze.txt",
        "protected_artifact_integrity.json",
        "registry_entry.json",
        "source_snapshot/__init__.py",
        "source_snapshot/hbv_adapter.py",
        "source_snapshot/hbv_lite_numpy.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/synthetic_truth.py",
        "source_snapshot/test_hbv_synthetic_truth.py",
        "summary.json",
    }
)


def _json_write(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _atomic_json_write(path: Path, value) -> None:
    temporary = path.with_name(path.name + ".incomplete")
    if path.exists() or temporary.exists():
        raise FileExistsError(f"refusing to overwrite registry file {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    _json_write(temporary, value)
    temporary.replace(path)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _protected_hashes(root: Path, configured_paths) -> dict[str, str]:
    hashes = {}
    for configured in configured_paths:
        path = (root / str(configured)).resolve()
        try:
            path.relative_to(root)
        except ValueError as error:
            raise ValueError(f"protected path is outside the repository: {configured}") from error
        if not path.exists():
            raise FileNotFoundError(f"protected path does not exist: {configured}")
        files = [path] if path.is_file() else sorted(item for item in path.rglob("*") if item.is_file())
        for item in files:
            hashes[item.relative_to(root).as_posix()] = _sha256(item)
    return hashes


def _git_value(root: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", *arguments], cwd=root, capture_output=True, text=True, check=False
    )
    if completed.returncode != 0:
        return f"unavailable: {completed.stderr.strip()}"
    return completed.stdout.rstrip()


def _dependency_manifests() -> tuple[list[dict], list[dict], str, str | None]:
    installed = []
    for distribution in importlib.metadata.distributions():
        direct_url_text = distribution.read_text("direct_url.json")
        installed.append(
            {
                "name": distribution.metadata.get("Name", distribution.name),
                "version": distribution.version,
                "installer": (distribution.read_text("INSTALLER") or "").strip() or None,
                "direct_url": json.loads(direct_url_text) if direct_url_text else None,
            }
        )
    installed.sort(key=lambda item: (item["name"].lower(), item["version"]))

    conda_packages = []
    conda_metadata = Path(sys.prefix) / "conda-meta"
    if conda_metadata.is_dir():
        for path in sorted(conda_metadata.glob("*.json")):
            with path.open("r", encoding="utf-8") as handle:
                value = json.load(handle)
            conda_packages.append(
                {
                    key: value.get(key)
                    for key in (
                        "name",
                        "version",
                        "build",
                        "build_number",
                        "channel",
                        "subdir",
                        "fn",
                        "md5",
                        "sha256",
                    )
                }
            )
    conda_packages.sort(key=lambda item: (str(item["name"]).lower(), str(item["version"])))

    completed = subprocess.run(
        [sys.executable, "-m", "pip", "freeze", "--all"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode == 0:
        pip_freeze = completed.stdout.rstrip() + "\n"
        pip_freeze_error = None
    else:
        requirements = sorted(
            {f"{item['name']}=={item['version']}" for item in installed}, key=str.lower
        )
        pip_freeze = (
            "# Generated from installed distribution metadata because pip freeze failed.\n"
            + "\n".join(requirements)
            + "\n"
        )
        pip_freeze_error = completed.stderr.strip()
    return installed, conda_packages, pip_freeze, pip_freeze_error


def _environment_manifest(root: Path, started_at: str) -> tuple[dict, str, list[dict], list[dict], str]:
    try:
        import numba

        numba_version = numba.__version__
    except Exception:
        numba_version = None
    try:
        import llvmlite

        llvmlite_version = llvmlite.__version__
    except Exception:
        llvmlite_version = None
    import scl_hydro.hbv_lite_numpy as reference_module

    git_status = _git_value(root, "status", "--short", "--untracked-files=all")
    installed_packages, conda_packages, pip_freeze, pip_freeze_error = _dependency_manifests()
    manifest = {
        "started_at_utc": started_at,
        "finished_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "execution_command": subprocess.list2cmdline(sys.argv),
        "working_directory": str(Path.cwd().resolve()),
        "operating_system": platform.platform(),
        "python_version": sys.version,
        "python_executable": sys.executable,
        "numpy_version": np.__version__,
        "numba_version": numba_version,
        "llvmlite_version": llvmlite_version,
        "reference_numba_enabled": bool(reference_module._HAS_NUMBA),
        "pip_freeze_method": "pip freeze --all" if pip_freeze_error is None else "installed distribution metadata",
        "pip_freeze_error": pip_freeze_error,
        "git_commit": _git_value(root, "rev-parse", "HEAD"),
        "git_worktree_dirty": bool(git_status),
        "environment_variables": {
            "DISABLE_NUMBA": os.environ.get("DISABLE_NUMBA"),
            "HBV_BOUNDS": os.environ.get("HBV_BOUNDS"),
        },
    }
    return manifest, git_status, installed_packages, conda_packages, pip_freeze


def _verify_complete_output(output: Path, expected_config: dict) -> tuple[dict, dict]:
    with (output / "checksums.json").open("r", encoding="utf-8") as handle:
        checksums = json.load(handle)
    if set(checksums) != REQUIRED_EVIDENCE_FILES:
        missing = sorted(REQUIRED_EVIDENCE_FILES - set(checksums))
        unexpected = sorted(set(checksums) - REQUIRED_EVIDENCE_FILES)
        raise ValueError(
            f"required evidence manifest mismatch; missing={missing}, unexpected={unexpected}"
        )
    actual_files = {
        path.relative_to(output).as_posix()
        for path in output.rglob("*")
        if path.is_file()
    }
    expected_files = REQUIRED_EVIDENCE_FILES | {"checksums.json"}
    if actual_files != expected_files:
        missing = sorted(expected_files - actual_files)
        unexpected = sorted(actual_files - expected_files)
        raise ValueError(
            f"required evidence file set mismatch; missing={missing}, unexpected={unexpected}"
        )
    for relative, expected in checksums.items():
        path = output / relative
        if not path.is_file() or _sha256(path) != expected:
            raise ValueError(f"existing evidence checksum mismatch: {relative}")
    with (output / "config_snapshot.json").open("r", encoding="utf-8") as handle:
        saved_config = json.load(handle)
    if saved_config != expected_config:
        raise ValueError("existing evidence config does not match the requested config")
    with (output / "summary.json").open("r", encoding="utf-8") as handle:
        summary = json.load(handle)
    with (output / "registry_entry.json").open("r", encoding="utf-8") as handle:
        registry_entry = json.load(handle)
    if registry_entry.get("experiment_id") != expected_config.get("experiment_id"):
        raise ValueError("existing evidence registry identity mismatch")
    return summary, registry_entry


def _forcing(config: dict) -> np.ndarray:
    forcing = config["forcing"]
    days = int(forcing["days"])
    if days <= 0:
        raise ValueError("forcing days must be positive")
    rng = np.random.default_rng(int(forcing["seed"]))
    rain = rng.gamma(float(forcing["rain_shape"]), float(forcing["rain_scale"]), size=days)
    angle = np.linspace(0.0, 2.0 * np.pi, days)
    potential_evaporation = np.maximum(0.0, 2.0 + np.sin(angle))
    temperature = 4.0 + 12.0 * np.sin(angle - np.pi / 2.0)
    return np.column_stack((rain, potential_evaporation, temperature)).astype(np.float64)


def _routing_shift_is_exact(states: np.ndarray) -> bool:
    expected = np.zeros_like(states[:, 5:])
    expected[:, 0] = states[:, 5]
    if len(states) > 1:
        expected[1:, 1:] = states[:-1, 5:14]
    return bool(np.array_equal(states[:, 5:], expected))


def run(repo_root: Path, config_path: Path, output_dir: Path, registry_path: Path) -> dict:
    root = repo_root.resolve()
    config_source = config_path.resolve()
    output = output_dir.resolve()
    registry = registry_path.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    with config_source.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    if output.name != str(config["experiment_id"]):
        raise ValueError("output directory name must equal experiment_id")
    if output.exists():
        if incomplete.exists():
            raise FileExistsError(f"both complete and incomplete evidence directories exist for {output}")
        if registry.exists():
            raise FileExistsError(f"refusing to overwrite completed evidence {output}")
        summary, registry_entry = _verify_complete_output(output, config)
        _atomic_json_write(registry, registry_entry)
        if summary.get("status") != "passed":
            raise RuntimeError(f"truth propagation validation failed; see {output / 'summary.json'}")
        return summary
    if incomplete.exists():
        raise FileExistsError(f"refusing to overwrite incomplete evidence directory {incomplete}")
    if registry.exists():
        raise FileExistsError(f"refusing to overwrite registry entry {registry}")

    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))

    forcing = _forcing(config)
    parameters = {name: float(value) for name, value in config["parameters"].items()}
    reference = generate_reference_truth(forcing, parameters)
    adapter_discharge, adapter_states = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters
    )
    state_error = float(np.max(np.abs(reference.states - adapter_states)))
    discharge_error = float(np.max(np.abs(reference.discharge - adapter_discharge)))
    raw_discharge_error = float(np.max(np.abs(reference.raw_discharge - adapter_states[:, 5])))
    finite = bool(
        np.all(np.isfinite(reference.states))
        and np.all(np.isfinite(adapter_states))
        and np.all(np.isfinite(reference.discharge))
        and np.all(np.isfinite(adapter_discharge))
    )
    reference_routing_shift_exact = _routing_shift_is_exact(reference.states)
    adapter_routing_shift_exact = _routing_shift_is_exact(adapter_states)
    routing_memory_cross_path_error = float(
        np.max(np.abs(reference.states[:, 5:] - adapter_states[:, 5:]))
    )
    thresholds = config["thresholds"]
    state_threshold = float(thresholds["state_maximum_absolute_error"])
    discharge_threshold = float(thresholds["discharge_maximum_absolute_error"])
    protected_after = _protected_hashes(root, config.get("protected_paths", ()))
    protected_unchanged = protected_before == protected_after
    passed = bool(
        finite
        and protected_unchanged
        and reference_routing_shift_exact
        and adapter_routing_shift_exact
        and routing_memory_cross_path_error <= state_threshold
        and state_error <= state_threshold
        and raw_discharge_error <= state_threshold
        and discharge_error <= discharge_threshold
    )
    summary = {
        "experiment_id": config["experiment_id"],
        "status": "passed" if passed else "failed",
        "days": int(len(forcing)),
        "finite": finite,
        "reference_routing_shift_exact": reference_routing_shift_exact,
        "adapter_routing_shift_exact": adapter_routing_shift_exact,
        "routing_memory_cross_path_maximum_absolute_error": routing_memory_cross_path_error,
        "state_maximum_absolute_error": state_error,
        "raw_discharge_maximum_absolute_error": raw_discharge_error,
        "discharge_maximum_absolute_error": discharge_error,
        "thresholds": {
            "state_maximum_absolute_error": state_threshold,
            "discharge_maximum_absolute_error": discharge_threshold,
        },
        "reference_path": "src/scl_hydro/hbv_lite_numpy.py",
        "tested_path": "src/hbv_joint_uncertainty/hbv_adapter.py",
        "protected_artifacts_unchanged": protected_unchanged,
    }
    registry_entry = {
        "experiment_id": config["experiment_id"],
        "type": "closed_truth_component_validation",
        "hypothesis": "the fifteen-state adapter and routed discharge match an independent HBV-lite replay",
        "changed_factor": "independent reference implementation",
        "fixed_factors": "forcing, initial stores, complete thirteen-parameter vector, and routing lag",
        "seed": int(config["forcing"]["seed"]),
        "status": summary["status"],
        "run_dir": str(output),
        "metrics_path": str(output / "summary.json"),
        "environment_path": str(output / "environment.json"),
        "protected_integrity_path": str(output / "protected_artifact_integrity.json"),
        "notes": "No real-basin observations or frozen formal results were read or modified.",
    }

    environment, git_status, installed_packages, conda_packages, pip_freeze = _environment_manifest(
        root, started_at
    )
    protected_integrity = {
        "configured_paths": list(config.get("protected_paths", ())),
        "before": protected_before,
        "after": protected_after,
        "status": "unchanged" if protected_unchanged else "changed",
    }

    incomplete.mkdir(parents=True)
    try:
        _json_write(incomplete / "config_snapshot.json", config)
        _json_write(incomplete / "summary.json", summary)
        _json_write(incomplete / "registry_entry.json", registry_entry)
        _json_write(incomplete / "environment.json", environment)
        _json_write(incomplete / "installed_packages.json", installed_packages)
        _json_write(incomplete / "conda_packages.json", conda_packages)
        _json_write(incomplete / "protected_artifact_integrity.json", protected_integrity)
        (incomplete / "git_status.txt").write_text(git_status + "\n", encoding="utf-8")
        (incomplete / "pip_freeze.txt").write_text(pip_freeze, encoding="utf-8")
        np.savez_compressed(
            incomplete / "evidence.npz",
            forcing=forcing,
            reference_states=reference.states,
            adapter_states=adapter_states,
            reference_discharge=reference.discharge,
            adapter_discharge=adapter_discharge,
            raw_discharge=reference.raw_discharge,
        )
        snapshot = incomplete / "source_snapshot"
        snapshot.mkdir()
        sources = {
            "__init__.py": root / "src" / "hbv_multilead_joint_uncertainty" / "__init__.py",
            "synthetic_truth.py": root / "src" / "hbv_multilead_joint_uncertainty" / "synthetic_truth.py",
            "run_synthetic_truth_validation.py": Path(__file__).resolve(),
            "hbv_adapter.py": root / "src" / "hbv_joint_uncertainty" / "hbv_adapter.py",
            "hbv_lite_numpy.py": root / "src" / "scl_hydro" / "hbv_lite_numpy.py",
            "test_hbv_synthetic_truth.py": root / "test" / "test_hbv_synthetic_truth.py",
        }
        for name, source in sources.items():
            shutil.copy2(source, snapshot / name)
        checksum_paths = sorted(
            path for path in incomplete.rglob("*") if path.is_file() and path.name != "checksums.json"
        )
        checksums = {
            path.relative_to(incomplete).as_posix(): _sha256(path)
            for path in checksum_paths
        }
        if set(checksums) != REQUIRED_EVIDENCE_FILES:
            missing = sorted(REQUIRED_EVIDENCE_FILES - set(checksums))
            unexpected = sorted(set(checksums) - REQUIRED_EVIDENCE_FILES)
            raise ValueError(
                f"required evidence manifest mismatch; missing={missing}, unexpected={unexpected}"
            )
        _json_write(incomplete / "checksums.json", checksums)
        incomplete.replace(output)
        _atomic_json_write(registry, registry_entry)
    except Exception:
        if incomplete.exists():
            shutil.rmtree(incomplete)
        raise
    if not passed:
        raise RuntimeError(f"truth propagation validation failed; see {output / 'summary.json'}")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--registry-path", type=Path, required=True)
    args = parser.parse_args()
    run(args.repo_root, args.config, args.output_dir, args.registry_path)


if __name__ == "__main__":
    main()
