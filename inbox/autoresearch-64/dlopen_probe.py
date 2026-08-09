"""Run three isolated candidate dependency probes under the real sandbox."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path

from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor
from unified_autoresearch.runtime.layout import create_run_layout
from unified_autoresearch.runtime.runner import run_candidate


EVIDENCE_ROOT = Path(
    "/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/"
    "dlopen_dependency_probe_20260809_seq19"
)
PROJECT_ROOT = Path("/data1/home/sunyiq/autoresearch64")
RUNTIME_SOURCE_FILES = (
    "src/unified_autoresearch/runtime/adapter.py",
    "src/unified_autoresearch/runtime/bootstrap.py",
    "src/unified_autoresearch/runtime/dependencies.py",
    "src/unified_autoresearch/runtime/descriptor.py",
    "src/unified_autoresearch/runtime/layout.py",
    "src/unified_autoresearch/runtime/outputs.py",
    "src/unified_autoresearch/runtime/runner.py",
)
DECLARATIONS = (
    ("numpy", "numpy==1.26.4"),
    ("pandas", "pandas==2.2.3"),
    ("pyarrow", "pyarrow==17.0.0"),
)
TRACE_PREFIX = "DLOPEN_TRACE="
TRACE_SOURCE = r'''
import json
import sys
import traceback

PREFIX = "DLOPEN_TRACE="

def audit(event, arguments):
    if event != "ctypes.dlopen":
        return
    frames = []
    for frame in traceback.extract_stack()[-40:]:
        frames.append({
            "filename": frame.filename,
            "lineno": frame.lineno,
            "name": frame.name,
            "line": frame.line,
        })
    value = {
        "event": event,
        "arguments": [repr(value) for value in arguments],
        "stack": frames,
    }
    print(PREFIX + json.dumps(value, sort_keys=True), flush=True)

sys.addaudithook(audit)
__import__(sys.argv[1])
'''


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json_exclusive(path: Path, value: object) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")


def _write_text_exclusive(path: Path, value: str) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(value)


def _descriptor_value(package: str, declaration: str) -> dict:
    return {
        "schema_version": "candidate_descriptor_v1",
        "candidate_id": f"dlopen-probe-{package}-v1",
        "category": "custom_python",
        "entrypoint": {"train": "entrypoint.py", "predict": "entrypoint.py"},
        "dependencies": [declaration],
        "allowed_reads": {
            "train": ["train_features.parquet", "train_targets.parquet", "static_attributes.json"],
            "predict": ["predict_features.parquet", "static_attributes.json", "model_artifacts"],
        },
        "outputs": {"train": ["model_artifacts"], "predict": ["predictions.parquet"]},
        "seed": 29,
        "resources": {
            "cpu_cores": 1,
            "gpu_count": 0,
            "estimated_peak_memory_gb": 0.1,
            "memory_safety_reserve_gb": 0.1,
            "estimated_output_gb": 0.001,
            "disk_safety_reserve_gb": 0.01,
            "independent_monitor_enabled": False,
            "monitor_reason": "minimal declared-dependency import diagnostic",
        },
        "checkpoint": {"supported": True, "staging_dir": "checkpoint_staging", "keep": "all"},
        "resume": {"supported": True},
    }


def _run_trace(package: str, trace_root: Path) -> dict:
    completed = subprocess.run(
        [sys.executable, "-I", "-B", "-c", TRACE_SOURCE, package],
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    stdout_path = trace_root / f"{package}.stdout.txt"
    stderr_path = trace_root / f"{package}.stderr.txt"
    _write_text_exclusive(stdout_path, completed.stdout)
    _write_text_exclusive(stderr_path, completed.stderr)
    events = []
    for line in completed.stdout.splitlines():
        if line.startswith(TRACE_PREFIX):
            events.append(json.loads(line[len(TRACE_PREFIX) :]))
    return {
        "role": "supporting non-blocking audit trace for the exact call stack",
        "exit_code": completed.returncode,
        "ctypes_dlopen_events": events,
        "stdout_path": str(stdout_path),
        "stderr_path": str(stderr_path),
    }


def _run_one(package: str, declaration: str, shared_inputs: Path, trace_root: Path) -> dict:
    source_root = EVIDENCE_ROOT / "candidate_sources" / package
    source_root.mkdir(parents=True)
    _write_text_exclusive(
        source_root / "entrypoint.py",
        "import os\n"
        "import sys\n"
        "from pathlib import Path\n"
        "\n"
        "mode = sys.argv[1]\n"
        "output_root = Path(os.environ['UNIFIED_OUTPUT_ROOT'])\n"
        "if mode == 'train':\n"
        "    (output_root / 'model_artifacts').mkdir()\n"
        "else:\n"
        "    (output_root / 'predictions.parquet').write_bytes(b'')\n",
    )
    descriptor_path = source_root / "candidate-descriptor.json"
    _write_json_exclusive(descriptor_path, _descriptor_value(package, declaration))
    descriptor = load_and_validate_candidate_descriptor(descriptor_path, candidate_root=source_root)
    layout = create_run_layout(
        EVIDENCE_ROOT / "runs" / package,
        descriptor=descriptor,
        candidate_source_root=source_root,
        mode="train",
        input_sources={
            "train_features.parquet": shared_inputs / "train_features.parquet",
            "train_targets.parquet": shared_inputs / "train_targets.parquet",
            "static_attributes.json": shared_inputs / "static_attributes.json",
        },
    )
    result = run_candidate(descriptor=descriptor, layout=layout, mode="train")
    events = [
        json.loads(line)
        for line in result.access_log_path.read_text(encoding="utf-8").splitlines()
        if line
    ]
    denied_dlopen = [
        event
        for event in events
        if event.get("event") == "ctypes.dlopen" and event.get("decision") == "deny"
    ]
    preflight = json.loads(result.dependency_preflight_path.read_text(encoding="utf-8"))
    runtime_result = json.loads(result.result_path.read_text(encoding="utf-8"))
    trace_result = _run_trace(package, trace_root)
    value = {
        "package": package,
        "declaration": declaration,
        "dependency_preflight": preflight,
        "sandbox": {
            "process_exit_code": result.process_exit_code,
            "normalized_exit_code": result.exit_code,
            "status": result.status,
            "denied_event_count": result.denied_event_count,
            "ctypes_dlopen_denied": bool(denied_dlopen),
            "ctypes_dlopen_denials": denied_dlopen,
            "last_12_access_events": events[-12:],
            "access_log_path": str(result.access_log_path),
            "runtime_result": runtime_result,
        },
        "trace": trace_result,
    }
    _write_json_exclusive(EVIDENCE_ROOT / f"PROBE_{package}.json", value)
    if preflight.get("decision") != "launch":
        raise RuntimeError(f"{package}: dependency preflight did not launch")
    if result.process_exit_code not in {0, 2}:
        raise RuntimeError(f"{package}: unexpected sandbox exit {result.process_exit_code}")
    if trace_result["exit_code"] != 0:
        raise RuntimeError(f"{package}: supporting trace failed")
    return value


def _write_manifest() -> None:
    rows = []
    for path in sorted(path for path in EVIDENCE_ROOT.rglob("*") if path.is_file()):
        if path.name == "MANIFEST.sha256":
            continue
        rows.append(f"{_sha256(path)}  {path.relative_to(EVIDENCE_ROOT).as_posix()}")
    _write_text_exclusive(EVIDENCE_ROOT / "MANIFEST.sha256", "\n".join(rows) + "\n")
    for path in EVIDENCE_ROOT.rglob("*"):
        if path.is_file():
            path.chmod(0o444)


def main() -> int:
    EVIDENCE_ROOT.mkdir(parents=True, exist_ok=False)
    shared_inputs = EVIDENCE_ROOT / "declared_inputs"
    trace_root = EVIDENCE_ROOT / "supporting_traces"
    shared_inputs.mkdir()
    trace_root.mkdir()
    _write_text_exclusive(shared_inputs / "train_features.parquet", "")
    _write_text_exclusive(shared_inputs / "train_targets.parquet", "")
    _write_text_exclusive(shared_inputs / "static_attributes.json", "{}\n")
    summary = {
        "schema_version": "dlopen_dependency_probe_v1",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "evidence_root": str(EVIDENCE_ROOT),
        "python_executable": sys.executable,
        "python_version": sys.version,
        "driver_path": str(Path(__file__).resolve()),
        "driver_sha256": _sha256(Path(__file__).resolve()),
        "runtime_source_sha256": {
            relative: _sha256(PROJECT_ROOT / relative) for relative in RUNTIME_SOURCE_FILES
        },
        "probes": [],
    }
    try:
        for package, declaration in DECLARATIONS:
            summary["probes"].append(_run_one(package, declaration, shared_inputs, trace_root))
        summary["diagnostic_complete"] = True
        _write_json_exclusive(EVIDENCE_ROOT / "SUMMARY.json", summary)
        _write_manifest()
        return 0
    except Exception as error:
        failure = {
            "diagnostic_complete": False,
            "error_type": type(error).__name__,
            "error": str(error),
            "traceback": traceback.format_exc(),
            "partial_summary": summary,
        }
        _write_json_exclusive(EVIDENCE_ROOT / "ERROR.json", failure)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
