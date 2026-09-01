from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import runpy
import sys
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parents[2]
CONFIG = HERE / "base_config.yaml"
COMBOS = HERE / "combos.jsonl"
REGISTRY = HERE / "registry.csv"
SOURCE_MANIFEST = HERE / "source_manifest.json"
GRID_RUNNER = PROJECT_ROOT / "experiments" / "optimize_hyper_parameters" / "grid_search_knet.py"
PYTHON_SEED = 42

EXPECTED_DATA = {
    "train": (
        PROJECT_ROOT / "data" / "processed" / "high_flow_aug" / "train_win800_19990101_01-20070527_03.pt",
        "3A4F94A2562278F09B67853AC77E060766296007CB8F8A762756FFE792792440",
    ),
    "val": (
        PROJECT_ROOT / "data" / "processed" / "high_flow_aug" / "val_win800_20070527_04-20090314_13.pt",
        "2E195FC974B5CC8CDB35DF3CB7FD72A202AF033ECC415ACC03A87020B00BD403",
    ),
}

RUN_IDS = {
    0: "WRR-HLRB-HPCBRIDGE-20260901-C0",
}


class Tee:
    def __init__(self, *streams):
        self.streams = streams

    def write(self, text):
        for stream in self.streams:
            stream.write(text)
            stream.flush()
        return len(text)

    def flush(self):
        for stream in self.streams:
            stream.flush()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def load_combo(index: int) -> dict:
    for line in COMBOS.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        item = json.loads(line)
        if int(item["index"]) == index:
            return item
    raise ValueError(f"Unknown combination index: {index}")


def guard_data_contract() -> dict:
    import yaml

    config = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
    paths = config.get("data", {}).get("dataset_path", {})
    if set(paths) != {"train", "val"}:
        raise RuntimeError(f"Dataset split guard failed: expected train/val only, got {sorted(paths)}")

    verified = {}
    for split, (expected_path, expected_hash) in EXPECTED_DATA.items():
        configured = Path(paths[split]).resolve()
        if configured != expected_path.resolve():
            raise RuntimeError(f"Unexpected {split} path: {configured}")
        if "test" in configured.name.lower():
            raise RuntimeError(f"Held-out test guard failed for {configured}")
        actual_hash = sha256(configured)
        if actual_hash != expected_hash:
            raise RuntimeError(
                f"{split} SHA-256 mismatch: expected {expected_hash}, got {actual_hash}"
            )
        verified[split] = {"path": str(configured), "sha256": actual_hash}
    return verified


def guard_source_contract() -> dict:
    manifest = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    expected = manifest.get("source_sha256", {})
    if not expected:
        raise RuntimeError("Source manifest has no source_sha256 entries")
    verified = {}
    for relative_path, expected_hash in expected.items():
        path = PROJECT_ROOT / relative_path
        actual_hash = sha256(path)
        if actual_hash != expected_hash:
            raise RuntimeError(
                f"Source SHA-256 mismatch for {relative_path}: "
                f"expected {expected_hash}, got {actual_hash}"
            )
        verified[relative_path] = actual_hash
    return verified


def configure_reproducibility():
    for name in (
        "BATCH_SIZE",
        "BATCH_SCALE",
        "MAX_TRAIN_BATCHES",
        "MAX_VAL_BATCHES",
        "MAX_BATCHES",
        "ONE_BATCH",
        "TEST_ABORT_AFTER_EPOCH",
        "RESUME",
        "PURGE_CKPTS",
    ):
        os.environ.pop(name, None)

    os.environ["PYTHONHASHSEED"] = str(PYTHON_SEED)
    os.environ["CUBLAS_WORKSPACE_CONFIG"] = ":4096:8"
    os.environ["DATA_BASE"] = str(PROJECT_ROOT)
    os.environ["DISABLE_AUTO_WORKERS"] = "1"
    os.environ["DISABLE_PIN_MEMORY"] = "1"
    os.environ["DISABLE_DATASET_CACHE"] = "1"
    os.environ["NO_TQDM"] = "1"
    os.environ["VALIDATION_QUIET"] = "1"
    os.environ["LOG_MODE"] = "compact"
    os.environ["PERF_INTERVAL"] = "0"
    os.environ["EPOCH_REPORT_EVERY"] = "1"

    import random
    import numpy as np
    import torch

    random.seed(PYTHON_SEED)
    np.random.seed(PYTHON_SEED)
    torch.manual_seed(PYTHON_SEED)
    torch.cuda.manual_seed_all(PYTHON_SEED)
    torch.backends.cudnn.deterministic = False
    torch.backends.cudnn.benchmark = True
    torch.use_deterministic_algorithms(False)

    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is unavailable; formal CPU fallback is forbidden")

    original_torch_load = torch.load

    def held_out_guarded_torch_load(file, *args, **kwargs):
        try:
            name = Path(os.fspath(file)).name.lower()
        except TypeError:
            name = ""
        if name.startswith("test_") or "held_out_test" in name:
            raise RuntimeError(f"Held-out test load blocked by launcher: {file}")
        return original_torch_load(file, *args, **kwargs)

    torch.load = held_out_guarded_torch_load

    return {
        "seed": PYTHON_SEED,
        "reproducibility_mode": "seeded_standard_backend",
        "deterministic_algorithms": torch.are_deterministic_algorithms_enabled(),
        "cudnn_deterministic": torch.backends.cudnn.deterministic,
        "cudnn_benchmark_before_training_entry": torch.backends.cudnn.benchmark,
        "torch_version": torch.__version__,
        "cuda_version": torch.version.cuda,
        "cudnn_version": torch.backends.cudnn.version(),
        "gpu": torch.cuda.get_device_name(0),
        "held_out_torch_load_guard": True,
    }


def expected_run_dir(base: Path, combo: dict) -> Path:
    lr = float(combo["lr"])
    if lr >= 1e-2:
        lr_label = f"{lr:.4f}".rstrip("0").rstrip(".").replace(".", "p")
    else:
        lr_label = f"{lr:.0e}"
    return base / (
        f"idx{int(combo['index']):04d}_lr{lr_label}_hs{int(combo['hidden_size'])}"
        f"_nl{int(combo['num_layers'])}_mult{int(combo['in_out_mult'])}"
    )


def update_registry(index: int, metrics_path: Path):
    rows = []
    with REGISTRY.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames
        rows.extend(reader)
    if not fieldnames:
        raise RuntimeError("Registry has no header")

    metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
    for row in rows:
        if int(row["index"]) == index:
            row["status"] = str(metrics["status"])
            row["nse"] = repr(float(metrics["nse"]))
            row["duration_sec"] = str(metrics["duration_sec"])
            row["metrics_path"] = str(metrics_path.relative_to(PROJECT_ROOT)).replace("\\", "/")
            row["completed_at"] = str(metrics["time"])
            break

    with REGISTRY.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", type=int, required=True, choices=sorted(RUN_IDS))
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()

    if args.smoke and args.index != 0:
        raise SystemExit("Smoke check is restricted to index 0")

    combo = load_combo(args.index)
    verified_source = guard_source_contract()
    verified_data = guard_data_contract()
    runtime = configure_reproducibility()

    mode = "smoke_seeded_standard" if args.smoke else "formal"
    out_base = HERE / "runs" / mode
    actual_out_base = Path(str(out_base) + "_gpu")
    run_dir = expected_run_dir(actual_out_base, combo)
    log_dir = HERE / "logs"
    audit_dir = HERE / "audits"
    log_dir.mkdir(parents=True, exist_ok=True)
    audit_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"{RUN_IDS[args.index]}_{mode}.stdout.log"
    audit_path = audit_dir / f"{RUN_IDS[args.index]}_{mode}.json"

    audit = {
        "run_id": RUN_IDS[args.index],
        "mode": mode,
        "started_at": datetime.now().isoformat(timespec="seconds"),
        "combo": combo,
        "config": str(CONFIG),
        "config_sha256": sha256(CONFIG),
        "combos": str(COMBOS),
        "combos_sha256": sha256(COMBOS),
        "verified_data": verified_data,
        "verified_source": verified_source,
        "runtime": runtime,
        "held_out_test_loaded": False,
        "command_contract": {
            "groups": str(args.index),
            "ignore_shards": True,
            "require_gpu": True,
            "auto_suffix_outdir": True,
            "resume": True,
        },
    }
    audit_path.write_text(json.dumps(audit, indent=2), encoding="utf-8")

    runner_args = [
        str(GRID_RUNNER),
        "--config",
        str(CONFIG),
        "--combos-file",
        str(COMBOS),
        "--outdir",
        str(out_base),
        "--device",
        "cuda",
        "--groups",
        str(args.index),
        "--ignore-shards",
        "--auto-suffix-outdir",
        "--require-gpu",
        "--resume",
        "--minimal",
    ]
    if args.smoke:
        os.environ["MAX_TRAIN_BATCHES"] = "1"
        os.environ["MAX_VAL_BATCHES"] = "1"
        runner_args.extend(["--epochs", "1"])

    old_argv = sys.argv[:]
    original_stdout = sys.stdout
    original_stderr = sys.stderr
    exit_status = "unknown"
    try:
        with log_path.open("a", encoding="utf-8", buffering=1) as log_handle:
            tee_out = Tee(original_stdout, log_handle)
            tee_err = Tee(original_stderr, log_handle)
            with redirect_stdout(tee_out), redirect_stderr(tee_err):
                print(f"[Launcher] run_id={RUN_IDS[args.index]} mode={mode}")
                print(f"[Launcher] combo={combo}")
                print(f"[Launcher] data_guard=train+val only; hashes verified")
                sys.argv = runner_args
                runpy.run_path(str(GRID_RUNNER), run_name="__main__")
        metrics_path = run_dir / "metrics.json"
        if not metrics_path.is_file():
            raise RuntimeError(f"Run returned without metrics.json: {metrics_path}")
        if not args.smoke:
            update_registry(args.index, metrics_path)
        exit_status = "ok"
    except BaseException as exc:
        exit_status = f"failed: {type(exc).__name__}: {exc}"
        raise
    finally:
        sys.argv = old_argv
        audit["finished_at"] = datetime.now().isoformat(timespec="seconds")
        audit["launcher_status"] = exit_status
        audit["log_path"] = str(log_path)
        audit["expected_run_dir"] = str(run_dir)
        audit_path.write_text(json.dumps(audit, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
