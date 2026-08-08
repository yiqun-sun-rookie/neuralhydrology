"""Resumable serial orchestrator for the 24 formal version-09 main trainings (S4).

Design decision (2026-08-07, approved): the one-use authorization receipt is deliberately
NOT used here. It could only be consumed once, but 24 runs take roughly 34 hours across
several scheduler jobs, so a single interruption used to burn the receipt and strand every
finished run. The scientific guarantees do not live in that lock -- they live in the frozen
protocol, the sealed and hashed inputs, the frozen run order, and the secret holdout that is
drawn only after all predictions are sealed. All of those still hold.

Progress is therefore not remembered by the orchestrator; it is *derived* from the sealed
run directories every time it starts. A run counts as finished only if its directory carries
a seal whose recorded hashes still match the bytes on disk. Anything half-written is left
alone and reported, never silently deleted or resumed mid-epoch.
"""
from __future__ import annotations

from collections.abc import Mapping, Sequence
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

IDEA_ROOT = Path(__file__).resolve().parent
if str(IDEA_ROOT) not in sys.path:
    sys.path.insert(0, str(IDEA_ROOT))

from train_formal_v09 import FormalRunSpecV09, load_run_order_v09

_LEDGER_NAME = "training_progress.json"
_FAILURE_NAME = "training_attempt_01.failure.json"
_RUN_ORDER_RELATIVE = "src/26_historical_band_experts/configs/formal_v09_run_order.json"
_PROTOCOL_RELATIVE = "src/26_historical_band_experts/configs/formal_v09_protocol.json"
_INPUT_RELATIVE = "results/26_historical_band_experts/formal_v09/input_attempt_01"
_FORMAL_RELATIVE = "results/26_historical_band_experts/formal_v09"


class SuiteError(RuntimeError):
    """Raised when the suite cannot safely continue."""


def run_paths_v09(worktree_root: str | Path, spec: FormalRunSpecV09) -> tuple[Path, Path, Path]:
    """Final, in-progress and failed directories for one run."""
    root = Path(os.path.abspath(worktree_root)) / spec.results_root
    base = root / f"seed_{spec.seed}"
    return base, base.with_name(f"{base.name}.building"), base.with_name(f"{base.name}.failed")


def verify_completed_run_v09(run_dir: str | Path, spec: FormalRunSpecV09) -> dict:
    """A run is finished only if its seal still matches the bytes on disk."""
    from artifact_v09 import sha256_file

    run_dir = Path(run_dir)
    seal_path = run_dir / "seal.json"
    manifest_path = run_dir / "manifest.json"
    if not seal_path.is_file() or not manifest_path.is_file():
        raise SuiteError(f"run {spec.run_id} is not sealed")
    seal = json.loads(seal_path.read_text(encoding="utf-8"))
    if seal.get("status") != "sealed":
        raise SuiteError(f"run {spec.run_id} seal status drift")
    if seal.get("manifest_sha256") != sha256_file(manifest_path):
        raise SuiteError(f"run {spec.run_id} manifest hash drift")
    for item in seal.get("sealed_files", []):
        path = run_dir / item["relative_path"]
        if not path.is_file() or sha256_file(path) != item["sha256"]:
            raise SuiteError(f"run {spec.run_id} sealed file drift: {item['relative_path']}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "formal_training_complete":
        raise SuiteError(f"run {spec.run_id} manifest status drift")
    if manifest.get("variant") != spec.variant or int(manifest.get("seed", -1)) != spec.seed:
        raise SuiteError(f"run {spec.run_id} manifest identity drift")
    if manifest.get("trainable_parameters") != spec.trainable_parameters:
        raise SuiteError(f"run {spec.run_id} parameter count drift")
    return manifest


def scan_progress_v09(worktree_root: str | Path, specs: Sequence[FormalRunSpecV09]) -> dict:
    """Derive progress from the directories; the orchestrator keeps no memory of its own."""
    completed, pending, dirty = [], [], []
    for spec in specs:
        final, building, failed = run_paths_v09(worktree_root, spec)
        if building.exists() or failed.exists():
            dirty.append(spec.run_id)
            continue
        if final.exists():
            verify_completed_run_v09(final, spec)
            completed.append(spec.run_id)
        else:
            pending.append(spec.run_id)
    return {
        "total": len(specs),
        "completed": completed,
        "pending": pending,
        "dirty": dirty,
    }


def _launch_run_v09(
    spec: FormalRunSpecV09,
    *,
    worktree_root: Path,
    output_dir: Path,
    protocol_path: Path,
    input_root: Path,
    device: str,
    python: str | None = None,
) -> int:
    command = [
        python or sys.executable,
        os.path.abspath(__file__),
        "--worker",
        "--run-id", spec.run_id,
        "--variant", spec.variant,
        "--seed", str(spec.seed),
        "--output-dir", str(output_dir),
        "--protocol", str(protocol_path),
        "--input-root", str(input_root),
        "--device", device,
    ]
    completed = subprocess.run(command, cwd=str(worktree_root), check=False)
    return int(completed.returncode)


def run_training_suite_v09(
    worktree_root: str | Path,
    *,
    device: str,
    protocol_path: str | Path | None = None,
    input_root: str | Path | None = None,
    run_order_path: str | Path | None = None,
    formal_root: str | Path | None = None,
    max_runs: int | None = None,
    launcher=_launch_run_v09,
) -> dict:
    """Run every pending training in the frozen order; safe to call again after a stop."""
    worktree_root = Path(os.path.abspath(worktree_root))
    protocol_path = Path(protocol_path or worktree_root / _PROTOCOL_RELATIVE)
    input_root = Path(input_root or worktree_root / _INPUT_RELATIVE)
    formal_root = Path(formal_root or worktree_root / _FORMAL_RELATIVE)
    specs = load_run_order_v09(run_order_path or worktree_root / _RUN_ORDER_RELATIVE)

    progress = scan_progress_v09(worktree_root, specs)
    if progress["dirty"]:
        raise SuiteError(
            "half-written or failed run directories need a human decision before resuming: "
            f"{progress['dirty']}")

    started, finished = [], []
    by_id = {spec.run_id: spec for spec in specs}
    for run_id in progress["pending"]:
        if max_runs is not None and len(finished) >= max_runs:
            break
        spec = by_id[run_id]
        final, building, failed = run_paths_v09(worktree_root, spec)
        building.parent.mkdir(parents=True, exist_ok=True)
        started.append(run_id)
        code = launcher(
            spec,
            worktree_root=worktree_root,
            output_dir=building,
            protocol_path=protocol_path,
            input_root=input_root,
            device=device,
            python=None,
        )
        if code != 0:
            if building.exists():
                building.rename(failed)
            _write_failure_v09(formal_root, spec, code, progress, finished)
            raise SuiteError(f"run {run_id} exited {code}; suite stopped, finished runs kept")
        if not building.exists():
            raise SuiteError(f"run {run_id} reported success but produced no directory")
        building.rename(final)
        verify_completed_run_v09(final, spec)
        finished.append(run_id)
        _write_ledger_v09(formal_root, worktree_root, specs)

    final_progress = scan_progress_v09(worktree_root, specs)
    return {
        "schema": "historical_multiscale_formal_v09_training_suite_v1",
        "status": "suite_complete" if not final_progress["pending"] else "suite_incomplete",
        "device": device,
        "started_this_call": started,
        "finished_this_call": finished,
        "progress": final_progress,
    }


def _write_ledger_v09(formal_root: Path, worktree_root: Path, specs) -> None:
    from artifact_v09 import write_json_atomic

    formal_root.mkdir(parents=True, exist_ok=True)
    path = formal_root / _LEDGER_NAME
    payload = {
        "schema": "historical_multiscale_formal_v09_training_progress_v1",
        "progress": scan_progress_v09(worktree_root, specs),
    }
    if path.exists():
        path.unlink()
    write_json_atomic(path, payload)


def _write_failure_v09(formal_root: Path, spec, code: int, progress: Mapping, finished) -> None:
    from artifact_v09 import write_json_atomic

    formal_root.mkdir(parents=True, exist_ok=True)
    path = formal_root / _FAILURE_NAME
    if path.exists():
        return
    write_json_atomic(
        path, {
            "schema": "historical_multiscale_formal_v09_training_failure_v1",
            "status": "run_failed",
            "run_id": spec.run_id,
            "variant": spec.variant,
            "seed": spec.seed,
            "exit_code": code,
            "completed_before_this_call": list(progress["completed"]),
            "finished_this_call": list(finished),
        })


# ---- command line -----------------------------------------------------------------------


def _worker(args) -> int:
    from formal_training_data_v09 import load_sealed_training_inputs_v09
    from formal_v09_protocol import load_protocol_v09
    from train_formal_v09 import run_training_v09

    worktree_root = Path(os.path.abspath(os.getcwd()))
    protocol_path = Path(args.protocol)
    protocol = load_protocol_v09(protocol_path)
    formal_root = Path(args.input_root).parent
    inputs = load_sealed_training_inputs_v09(
        Path(args.input_root),
        protocol_path,
        worktree_root=worktree_root,
        external_audit_path=formal_root / "input_attempt_01.external_audit.json",
        trusted_source_audit_path=formal_root / "input_attempt_01.trusted_source_external_audit.json",
    )
    manifest = run_training_v09(
        inputs,
        variant=args.variant,
        seed=args.seed,
        output_dir=Path(args.output_dir),
        device=args.device,
        protocol=protocol,
    )
    print(json.dumps({"run_id": args.run_id, "status": manifest["status"]}, sort_keys=True))
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="formal version 09 main-training suite")
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--run-id")
    parser.add_argument("--variant")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--output-dir")
    parser.add_argument("--protocol")
    parser.add_argument("--input-root")
    parser.add_argument("--device", default="cuda:0")
    parser.add_argument("--worktree-root", default=".")
    parser.add_argument("--max-runs", type=int)
    args = parser.parse_args(argv)
    if args.worker:
        return _worker(args)
    result = run_training_suite_v09(
        args.worktree_root,
        device=args.device,
        protocol_path=args.protocol,
        input_root=args.input_root,
        max_runs=args.max_runs,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
