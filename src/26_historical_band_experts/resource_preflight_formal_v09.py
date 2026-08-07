"""Synthetic resource preflight for the formal version-09 training stage (S3).

Four frozen workloads, each executed in two sequentially launched throwaway subprocesses on
purely synthetic data. The two runs must agree on every numeric array hash; only peak
device memory may differ. The workers accept a workload name, a device and shape integers
and nothing else -- no path is reachable from the command line, so a worker can neither open
the sealed inputs nor write into a formal output directory. Only the parent writes a report,
and only after every worker has exited.
"""
from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

IDEA_ROOT = Path(__file__).resolve().parent
if str(IDEA_ROOT) not in sys.path:
    sys.path.insert(0, str(IDEA_ROOT))

_STATUS = "complete_resource_preflight"
_SCHEMA = "historical_multiscale_formal_v09_resource_preflight_v1"
_REPORT_RELATIVE = (
    "results/26_historical_band_experts/formal_v09/training_resource_preflight.external_audit.json")

# Frozen formal geometry; tests override with a small profile so they can run on CPU.
FORMAL_PROFILE_V09 = {"batch_size": 256, "recent_days": 270, "window_days": 3562, "statics": 27, "features": 5}


@dataclass(frozen=True)
class WorkloadV09:
    name: str
    variants: tuple[str, ...]
    needs_history: bool


WORKLOADS_V09 = (
    WorkloadV09("strict_nesting_pair", ("classic_lstm_256_clean", "nested_history_disabled"), False),
    WorkloadV09("classic_lstm_256_clean", ("classic_lstm_256_clean",), False),
    WorkloadV09("classic_lstm_369_capacity", ("classic_lstm_369_capacity",), False),
    WorkloadV09("continuous_multiscale_history", ("continuous_multiscale_history",), True),
)
_BY_NAME = {workload.name: workload for workload in WORKLOADS_V09}


class ResourcePreflightError(RuntimeError):
    """Raised when the two independent preflight runs disagree."""


def _sha256_tensor(tensor) -> str:
    return hashlib.sha256(tensor.detach().cpu().contiguous().numpy().tobytes()).hexdigest()


def _freeze_determinism_v09() -> dict:
    import torch

    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False
    try:
        torch.use_deterministic_algorithms(True, warn_only=True)
        requested = True
    except Exception:  # older builds refuse some ops outright
        requested = False
    return {
        "cudnn_deterministic": bool(torch.backends.cudnn.deterministic),
        "cudnn_benchmark": bool(torch.backends.cudnn.benchmark),
        "deterministic_algorithms_requested": requested,
        "cublas_workspace_config": os.environ.get("CUBLAS_WORKSPACE_CONFIG", ""),
    }


def run_workload_in_process_v09(name: str, *, device: str, profile: Mapping, seed: int = 29_090) -> dict:
    """One forward, loss, backward and Adam step on synthetic data; returns hashes only."""
    import torch

    from models_formal_v09 import build_model_v09
    from train_strict_v06 import active_named_parameters

    workload = _BY_NAME.get(name)
    if workload is None:
        raise ValueError(f"unknown preflight workload: {name}")
    switches = _freeze_determinism_v09()
    torch_device = torch.device(device)
    batch = int(profile["batch_size"])
    features = int(profile["features"])
    statics_size = int(profile["statics"])

    if torch_device.type == "cuda":
        # The allocator has no per-device state until CUDA is initialised, and resetting peak
        # stats before that raises "Invalid device argument". Bind the device first.
        torch.cuda.set_device(torch_device)
        torch.cuda.init()
        torch.cuda.empty_cache()
        torch.cuda.reset_peak_memory_stats(torch_device)

    generator = torch.Generator().manual_seed(seed)
    if workload.needs_history:
        from bands_formal_v09 import split_windows_v09

        windows = torch.randn(batch, int(profile["window_days"]), features, generator=generator)
        dynamic = {k: v.to(torch_device) for k, v in split_windows_v09(windows).items()}
        input_shapes = {"windows": list(windows.shape)}
    else:
        recent = torch.randn(batch, int(profile["recent_days"]), features, generator=generator)
        dynamic = {"recent": recent.to(torch_device)}
        input_shapes = {"recent": list(recent.shape)}
    statics = torch.randn(batch, statics_size, generator=generator).to(torch_device)
    target = torch.randn(batch, generator=generator).to(torch_device)
    weights = torch.ones(batch, device=torch_device)

    torch.manual_seed(seed)
    if torch_device.type == "cuda":
        torch.cuda.manual_seed_all(seed)

    models = []
    for variant in workload.variants:
        model = build_model_v09(variant, 100).to(torch_device)
        parameters = active_named_parameters(model)
        optimizer = torch.optim.Adam([p for _, p in parameters], lr=0.001)
        models.append((variant, model, optimizer, parameters))

    results = []
    for variant, model, optimizer, parameters in models:
        model.train()
        optimizer.zero_grad(set_to_none=True)
        prediction = model(dynamic, statics, dropout_context=(100, 1, 0)).prediction
        loss = (weights * torch.square(prediction - target)).mean()
        loss.backward()
        norm = torch.nn.utils.clip_grad_norm_([p for _, p in parameters], 1.0)
        optimizer.step()
        parameter_hash = hashlib.sha256()
        for name_, parameter in parameters:
            parameter_hash.update(name_.encode("utf-8"))
            parameter_hash.update(parameter.detach().cpu().contiguous().numpy().tobytes())
        adam_hash = hashlib.sha256()
        for _, parameter in parameters:
            state = optimizer.state[parameter]
            for key in ("exp_avg", "exp_avg_sq"):
                adam_hash.update(state[key].detach().cpu().contiguous().numpy().tobytes())
            adam_hash.update(str(int(state["step"])).encode("utf-8"))
        results.append({
            "variant": variant,
            "trainable_parameters": sum(p.numel() for _, p in parameters),
            "loss_sha256": hashlib.sha256(
                float(loss.detach().cpu()).hex().encode("utf-8")).hexdigest(),
            "gradient_norm_sha256": hashlib.sha256(
                float(norm.detach().cpu()).hex().encode("utf-8")).hexdigest(),
            "parameter_sha256": parameter_hash.hexdigest(),
            "adam_state_sha256": adam_hash.hexdigest(),
        })

    peak_allocated = None
    peak_reserved = None
    if torch_device.type == "cuda":
        peak_allocated = int(torch.cuda.max_memory_allocated(torch_device))
        peak_reserved = int(torch.cuda.max_memory_reserved(torch_device))
    return {
        "workload": name,
        "device_type": torch_device.type,
        "input_shapes": input_shapes,
        "models": results,
        "rng_state_sha256": _sha256_tensor(torch.get_rng_state()),
        "determinism": switches,
        "peak_allocated_bytes": peak_allocated,
        "peak_reserved_bytes": peak_reserved,
        "received_formal_input_path": False,
        "received_formal_output_path": False,
        "process_id": os.getpid(),
    }


# ---- comparison ------------------------------------------------------------------------

_VOLATILE_KEYS = ("peak_allocated_bytes", "peak_reserved_bytes", "process_id")


def _comparable(payload: Mapping) -> dict:
    return {k: v for k, v in payload.items() if k not in _VOLATILE_KEYS}


def compare_preflight_runs_v09(first: Mapping, second: Mapping) -> dict:
    """Everything except peak memory and the process id must match exactly."""
    left, right = _comparable(first), _comparable(second)
    if left != right:
        for key in sorted(set(left) | set(right)):
            if left.get(key) != right.get(key):
                raise ResourcePreflightError(f"preflight runs disagree on {key}")
        raise ResourcePreflightError("preflight runs disagree")
    return {
        "workload": first["workload"],
        "input_shapes": first["input_shapes"],
        "models": first["models"],
        "rng_state_sha256": first["rng_state_sha256"],
        "determinism": first["determinism"],
        "arrays_identical": True,
        "runs": [
            {
                "process_id": first.get("process_id"),
                "peak_allocated_bytes": first.get("peak_allocated_bytes"),
                "peak_reserved_bytes": first.get("peak_reserved_bytes"),
                "exit_code": first.get("exit_code", 0),
            },
            {
                "process_id": second.get("process_id"),
                "peak_allocated_bytes": second.get("peak_allocated_bytes"),
                "peak_reserved_bytes": second.get("peak_reserved_bytes"),
                "exit_code": second.get("exit_code", 0),
            },
        ],
        "peak_allocated_bytes": max(
            (v for v in (first.get("peak_allocated_bytes"), second.get("peak_allocated_bytes")) if v is not None),
            default=None),
        "peak_reserved_bytes": max(
            (v for v in (first.get("peak_reserved_bytes"), second.get("peak_reserved_bytes")) if v is not None),
            default=None),
    }


# ---- subprocess driver -----------------------------------------------------------------


def _launch_worker_v09(name: str, *, device: str, profile: Mapping, python: str | None = None) -> dict:
    """Start one throwaway worker; it receives no path of any kind."""
    command = [
        python or sys.executable,
        os.path.abspath(__file__),
        "--workload", name,
        "--device", device,
        "--batch-size", str(int(profile["batch_size"])),
        "--recent-days", str(int(profile["recent_days"])),
        "--window-days", str(int(profile["window_days"])),
        "--statics", str(int(profile["statics"])),
        "--features", str(int(profile["features"])),
    ]
    environment = dict(os.environ)
    environment.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")
    completed = subprocess.run(command, capture_output=True, text=True, env=environment, check=False)
    if completed.returncode != 0:
        raise ResourcePreflightError(
            f"preflight worker for {name} exited {completed.returncode}: {completed.stderr[-800:]}")
    payload = json.loads(completed.stdout.strip().splitlines()[-1])
    payload["exit_code"] = completed.returncode
    return payload


def run_preflight_workloads_v09(
    *,
    device: str,
    profile: Mapping | None = None,
    python: str | None = None,
    launcher=_launch_worker_v09,
) -> list[dict]:
    """Run every frozen workload twice, sequentially, and require agreement."""
    profile = dict(profile or FORMAL_PROFILE_V09)
    summaries = []
    for workload in WORKLOADS_V09:
        first = launcher(workload.name, device=device, profile=profile, python=python)
        second = launcher(workload.name, device=device, profile=profile, python=python)
        summaries.append(compare_preflight_runs_v09(first, second))
    return summaries


def run_resource_preflight_v09(
    protocol_path: str | Path,
    *,
    device: str,
    report_path: str | Path,
    profile: Mapping | None = None,
    python: str | None = None,
    launcher=_launch_worker_v09,
) -> dict:
    """Parent entry: run all workloads, then atomically publish one report."""
    from artifact_v09 import canonical_sha256, write_json_atomic
    from formal_v09_protocol import load_protocol_v09

    protocol_path = Path(os.path.abspath(protocol_path))
    report_path = Path(os.path.abspath(report_path))
    sealed_root = report_path.parent / "input_attempt_01"
    if sealed_root in report_path.parents or report_path.parent.name == "input_attempt_01":
        raise ValueError("resource preflight report must be outside the sealed input directory")
    if report_path.exists():
        raise FileExistsError(f"resource preflight report already exists: {report_path}")
    protocol = load_protocol_v09(protocol_path)
    workloads = run_preflight_workloads_v09(device=device, profile=profile, python=python, launcher=launcher)
    report = {
        "schema": _SCHEMA,
        "status": _STATUS,
        "device": device,
        "protocol_canonical_sha256": canonical_sha256(protocol),
        "profile": dict(profile or FORMAL_PROFILE_V09),
        "workload_count": len(workloads),
        "workloads": workloads,
        "opened_formal_inputs": False,
        "wrote_formal_outputs": False,
    }
    write_json_atomic(report_path, report)
    return report


# ---- worker command line ----------------------------------------------------------------


def _worker_main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="version 09 synthetic resource preflight worker")
    parser.add_argument("--workload", required=True, choices=tuple(_BY_NAME))
    parser.add_argument("--device", required=True)
    parser.add_argument("--batch-size", type=int, required=True)
    parser.add_argument("--recent-days", type=int, required=True)
    parser.add_argument("--window-days", type=int, required=True)
    parser.add_argument("--statics", type=int, required=True)
    parser.add_argument("--features", type=int, required=True)
    args = parser.parse_args(argv)
    profile = {
        "batch_size": args.batch_size,
        "recent_days": args.recent_days,
        "window_days": args.window_days,
        "statics": args.statics,
        "features": args.features,
    }
    payload = run_workload_in_process_v09(args.workload, device=args.device, profile=profile)
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(_worker_main())
