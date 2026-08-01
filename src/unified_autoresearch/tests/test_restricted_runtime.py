import json
import os
import stat
import subprocess
from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def _stable_resource_capacity(monkeypatch):
    """Keep behavioral tests independent of transient host memory pressure."""
    from unified_autoresearch.runtime.resources import ResourceSnapshot

    monkeypatch.setattr(
        "unified_autoresearch.runtime.runner.capture_resource_snapshot",
        lambda _path: ResourceSnapshot(
            available_cpu_cores=8,
            available_gpu_count=0,
            available_memory_gb=8.0,
            free_disk_gb=100.0,
        ),
    )


def _descriptor_value() -> dict:
    return {
        "schema_version": "candidate_descriptor_v1",
        "candidate_id": "runtime-candidate-001",
        "category": "custom_python",
        "entrypoint": {"train": "train.py", "predict": "predict.py"},
        "dependencies": [],
        "allowed_reads": {
            "train": ["train_features.parquet", "train_targets.parquet", "static_attributes.json"],
            "predict": ["predict_features.parquet", "static_attributes.json", "model_artifacts"],
        },
        "outputs": {"train": ["model_artifacts"], "predict": ["predictions.parquet"]},
        "seed": 23,
        "resources": {
            "cpu_cores": 1,
            "gpu_count": 0,
            "estimated_peak_memory_gb": 0.25,
            "memory_safety_reserve_gb": 0.25,
            "estimated_output_gb": 0.01,
            "disk_safety_reserve_gb": 0.10,
            "independent_monitor_enabled": False,
            "monitor_reason": "short deterministic contract test",
        },
        "checkpoint": {"supported": True, "staging_dir": "checkpoint_staging", "keep": "all"},
        "resume": {"supported": True},
    }


def _prepare_prediction_run(
    tmp_path: Path,
    predict_source: str,
    *,
    resource_overrides: dict | None = None,
    candidate_files: dict[str, str] | None = None,
    dependencies: list[str] | None = None,
):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor
    from unified_autoresearch.runtime.layout import create_run_layout

    candidate_root = tmp_path / "candidate_source"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    (candidate_root / "predict.py").write_text(predict_source, encoding="utf-8")
    for relative, content in (candidate_files or {}).items():
        target = candidate_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
    descriptor_path = tmp_path / "candidate.json"
    descriptor_value = _descriptor_value()
    if resource_overrides:
        descriptor_value["resources"].update(resource_overrides)
    if dependencies is not None:
        descriptor_value["dependencies"] = dependencies
    descriptor_path.write_text(json.dumps(descriptor_value), encoding="utf-8")
    descriptor = load_and_validate_candidate_descriptor(descriptor_path, candidate_root=candidate_root)

    inputs = tmp_path / "source_inputs"
    inputs.mkdir()
    (inputs / "predict_features.parquet").write_text("approved-features", encoding="utf-8")
    (inputs / "static_attributes.json").write_text("{}\n", encoding="utf-8")
    (inputs / "model_artifacts").mkdir()
    (inputs / "model_artifacts" / "model.bin").write_bytes(b"model")
    layout = create_run_layout(
        tmp_path / "run",
        descriptor=descriptor,
        candidate_source_root=candidate_root,
        mode="predict",
        input_sources={name: inputs / name for name in descriptor.allowed_reads["predict"]},
    )
    return descriptor, layout


def _read_access_events(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def _prediction_parquet_bytes(*, required_columns: bool = True) -> bytes:
    import io

    import pyarrow as pa
    import pyarrow.parquet as pq

    values = (
        {"basin": ["01013500"], "date": ["2000-01-01"], "qsim": [1.25]}
        if required_columns
        else {"unrelated": [1]}
    )
    stream = io.BytesIO()
    pq.write_table(pa.table(values), stream)
    return stream.getvalue()


def _publish_resume_checkpoint(tmp_path: Path, *, candidate_id: str = "runtime-candidate-001"):
    from unified_autoresearch.runtime.checkpoints import promote_staged_checkpoint

    staging = tmp_path / "resume_staging"
    staging.mkdir()
    payload = b"resume-state"
    (staging / "model.bin").write_bytes(payload)
    request = {
        "schema_version": "checkpoint_request_v1",
        "checkpoint_id": "resume-checkpoint-0001",
        "candidate_id": candidate_id,
        "mode": "predict",
        "parent_checkpoint_id": None,
        "files": {"model.bin": __import__("hashlib").sha256(payload).hexdigest()},
    }
    (staging / "CHECKPOINT_REQUEST.json").write_text(json.dumps(request), encoding="utf-8")
    checkpoints = tmp_path / "published_checkpoints"
    checkpoints.mkdir()
    return promote_staged_checkpoint(staging, checkpoints)


def test_restricted_runtime_allows_declared_read_and_output_write(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    prediction_bytes = _prediction_parquet_bytes()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f"""from pathlib import Path
import os
source = Path(os.environ["UNIFIED_INPUT_ROOT"]) / "predict_features.parquet"
target = Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet"
assert source.read_text(encoding="utf-8") == "approved-features"
target.write_bytes({prediction_bytes!r})
""",
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 0
    assert result.status == "succeeded"
    assert (layout.output_root / "predictions.parquet").read_bytes() == prediction_bytes
    assert result.output_contract_valid is True
    events = _read_access_events(result.access_log_path)
    assert any(event["decision"] == "allow" and event.get("operation") == "read" for event in events)
    assert any(event["decision"] == "allow" and event.get("operation") == "write" for event in events)
    preflight = json.loads(result.resource_preflight_path.read_text(encoding="utf-8"))
    assert preflight["decision"] == "launch"
    assert preflight["memory_fit"] is True
    assert preflight["disk_fit"] is True


def test_restricted_runtime_imports_sibling_candidate_module(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    prediction_bytes = _prediction_parquet_bytes()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        '''import os
from pathlib import Path
from helper import prediction_bytes

(Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet").write_bytes(prediction_bytes)
''',
        candidate_files={"helper.py": f"prediction_bytes = {prediction_bytes!r}\n"},
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 0
    assert result.status == "succeeded"
    assert result.output_contract_valid is True


@pytest.mark.parametrize(
    "dependency",
    ["packaging==0.0.0", "unified-autoresearch-package-that-does-not-exist==1.0.0"],
    ids=("wrong-version", "missing-package"),
)
def test_restricted_runtime_rejects_dependency_environment_mismatch_before_launch(tmp_path, dependency):
    from unified_autoresearch.runtime.runner import run_candidate

    prediction_bytes = _prediction_parquet_bytes()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f'''import os
from pathlib import Path
(Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet").write_bytes({prediction_bytes!r})
''',
        dependencies=[dependency],
    )

    with pytest.raises(RuntimeError, match="declared dependency environment does not match"):
        run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    preflight = json.loads((layout.log_root / "dependency-preflight.json").read_text(encoding="utf-8"))
    assert preflight["decision"] == "deny"
    assert preflight["requested"] == [dependency]
    assert not (layout.log_root / "runtime-policy.json").exists()
    assert not (layout.log_root / "access.jsonl").exists()


def test_restricted_runtime_accepts_one_exact_installed_dependency_version(tmp_path):
    import importlib.metadata
    import packaging

    from unified_autoresearch.runtime.runner import run_candidate

    installed_version = importlib.metadata.version("packaging")
    prediction_bytes = _prediction_parquet_bytes()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f'''import os
from pathlib import Path
import packaging
assert packaging.__version__ == {installed_version!r}
(Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet").write_bytes({prediction_bytes!r})
''',
        dependencies=[f"packaging=={installed_version}"],
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 0
    assert result.status == "succeeded"
    preflight = json.loads(result.dependency_preflight_path.read_text(encoding="utf-8"))
    assert preflight["decision"] == "launch"
    assert preflight["matches"][0]["installed_versions"] == [installed_version]
    assert preflight["initialization_probe_error"] is None
    assert preflight["initialization_read_roots"]
    policy = json.loads((layout.log_root / "runtime-policy.json").read_text(encoding="utf-8"))
    assert policy["restricted_site_package_roots"]
    assert policy["dependency_initialization_read_roots"] == preflight["initialization_read_roots"]
    assert not set(policy["restricted_site_package_roots"]) & set(policy["dependency_initialization_read_roots"])
    packaging_path = str(Path(packaging.__file__).resolve())
    assert any(
        os.path.commonpath((packaging_path, root)) == root
        for root in policy["dependency_initialization_read_roots"]
    )


def test_bootstrap_records_and_restricts_declared_dependency_initialization(tmp_path):
    import sysconfig

    from unified_autoresearch.runtime.adapter import build_candidate_command

    interpreter_root = tmp_path / "interpreter_root"
    site_packages_root = interpreter_root / "site-packages"
    dependency_root = site_packages_root / "audit_probe_dependency"
    dependency_root.mkdir(parents=True)
    outside_path = site_packages_root / "undeclared_dependency_input.txt"
    outside_path.write_text("not-authorized", encoding="utf-8")
    (dependency_root / "__init__.py").write_text(
        "from pathlib import Path\n"
        f"Path({str(outside_path)!r}).read_text(encoding='utf-8')\n",
        encoding="utf-8",
    )
    candidate_root = tmp_path / "candidate_source"
    candidate_root.mkdir()
    entrypoint = candidate_root / "predict.py"
    entrypoint.write_text("pass\n", encoding="utf-8")
    output_root = tmp_path / "outputs"
    checkpoint_root = tmp_path / "checkpoint_staging"
    output_root.mkdir()
    checkpoint_root.mkdir()
    policy_path = tmp_path / "runtime-policy.json"
    policy_path.write_text(
        json.dumps(
            {
                "schema_version": "runtime_policy_v1",
                "read_roots": [
                    str(candidate_root),
                    str(interpreter_root),
                    *[
                        value
                        for key, value in sysconfig.get_paths().items()
                        if key in {"stdlib", "platstdlib"} and value
                    ],
                ],
                "write_roots": [str(output_root), str(checkpoint_root)],
                "candidate_root": str(candidate_root),
                "allowed_dependency_imports": ["audit_probe_dependency"],
                "restricted_site_package_roots": [str(site_packages_root)],
                "dependency_initialization_read_roots": [str(dependency_root)],
            }
        ),
        encoding="utf-8",
    )
    access_log_path = tmp_path / "access.jsonl"
    environment = os.environ.copy()
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    environment["PYTHONPATH"] = str(site_packages_root)

    completed = subprocess.run(
        build_candidate_command(
            policy_path=policy_path,
            access_log_path=access_log_path,
            entrypoint=entrypoint,
            mode="predict",
        ),
        cwd=tmp_path,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert completed.returncode == 2
    events = _read_access_events(access_log_path)
    assert any(
        event.get("decision") == "deny"
        and str(outside_path).lower() == str(event.get("path", "")).lower()
        for event in events
    )


def test_dependency_preflight_binds_the_version_resolved_by_the_active_interpreter():
    import numpy

    from unified_autoresearch.runtime.dependencies import assess_dependency_environment

    assessment = assess_dependency_environment((f"numpy=={numpy.__version__}",))

    assert assessment.decision == "launch"
    match = assessment.as_dict()["matches"][0]
    assert match["active_version"] == numpy.__version__
    assert Path(match["active_module_path"]).resolve() == Path(numpy.__file__).resolve()
    assert numpy.__version__ in match["installed_versions"]


def test_restricted_runtime_allows_a_caught_import_of_a_module_that_is_not_installed(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    prediction_bytes = _prediction_parquet_bytes()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f'''import os
from pathlib import Path
try:
    import unified_autoresearch_optional_module_that_is_not_installed
except ImportError:
    pass
(Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet").write_bytes({prediction_bytes!r})
''',
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.status == "succeeded"
    assert result.denied_event_count == 0


def test_restricted_runtime_denies_real_open_outside_allowlist_and_logs_it(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    forbidden = tmp_path / "forbidden.txt"
    forbidden.write_text("must-not-be-read", encoding="utf-8")
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f"""from pathlib import Path
Path({str(forbidden)!r}).read_text(encoding="utf-8")
""",
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    assert result.denied_event_count >= 1
    events = _read_access_events(result.access_log_path)
    assert any(event["decision"] == "deny" for event in events)
    assert result.denied_event_count >= 1
    events = _read_access_events(result.access_log_path)
    denied = [event for event in events if event["decision"] == "deny"]
    assert any(Path(event["path"]).resolve() == forbidden.resolve() for event in denied)
    assert not (layout.output_root / "predictions.parquet").exists()


def test_candidate_cannot_suppress_a_caught_denial_by_replacing_os_write(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    forbidden = tmp_path / "hidden-denial.txt"
    forbidden.write_text("must-remain-forbidden", encoding="utf-8")
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f'''import os
from pathlib import Path
os.write = lambda descriptor, payload: len(payload)
try:
    Path({str(forbidden)!r}).read_text(encoding="utf-8")
except PermissionError:
    pass
(Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet").write_text("pretend-success", encoding="utf-8")
''',
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    assert result.denied_event_count >= 1
    events = _read_access_events(result.access_log_path)
    assert any(event["decision"] == "deny" and event.get("operation") == "read" for event in events)


def test_candidate_cannot_hide_a_denial_by_redirecting_the_audit_descriptor(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    forbidden = tmp_path / "descriptor-redirection-forbidden.txt"
    forbidden.write_text("must-not-be-copied", encoding="utf-8")
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f'''import os
from pathlib import Path
target = open(Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet", "wb")
os.dup2(target.fileno(), 3)
try:
    Path({str(forbidden)!r}).read_text(encoding="utf-8")
except PermissionError:
    pass
target.write(b"pretend-success")
target.flush()
''',
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    assert result.denied_event_count >= 1
    events = _read_access_events(result.access_log_path)
    assert any(event["decision"] == "deny" for event in events)


def test_candidate_cannot_redirect_path_checks_by_replacing_os_path_helpers(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    forbidden = tmp_path / "path-helper-forbidden.txt"
    forbidden.write_text("path-helper-secret", encoding="utf-8")
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f'''import os
from pathlib import Path
allowed = os.environ["UNIFIED_INPUT_ROOT"]
forbidden = {str(forbidden)!r}
original_abspath = os.path.abspath
original_realpath = os.path.realpath
os.path.abspath = lambda path: allowed if os.fspath(path) == forbidden else original_abspath(path)
os.path.realpath = lambda path: allowed if os.fspath(path) == forbidden else original_realpath(path)
payload = Path({str(forbidden)!r}).read_text(encoding="utf-8")
(Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet").write_text(payload, encoding="utf-8")
''',
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    assert result.denied_event_count >= 1
    assert not (layout.output_root / "predictions.parquet").exists()


@pytest.mark.parametrize(
    ("candidate_source", "denied_event"),
    [
        ("import psutil\n", "import"),
        ("import os\nos.system('exit 0')\n", "os.system"),
        ("import socket\nsocket.socket()\n", "socket.__new__"),
        (
            "import ctypes, os\nctypes.CDLL('kernel32.dll' if os.name == 'nt' else None)\n",
            "ctypes.dlopen",
        ),
    ],
    ids=("undeclared-dependency", "child-process", "network", "dynamic-local-library"),
)
def test_restricted_runtime_denies_unapproved_execution_capabilities(tmp_path, candidate_source, denied_event):
    from unified_autoresearch.runtime.runner import run_candidate

    descriptor, layout = _prepare_prediction_run(tmp_path, candidate_source)

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    events = _read_access_events(result.access_log_path)
    assert any(event["decision"] == "deny" and event["event"] == denied_event for event in events)


@pytest.mark.skipif(os.name != "nt", reason="Windows file-association launch is Windows-specific")
def test_restricted_runtime_classifies_startfile_as_a_disabled_child_process(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    missing_target = tmp_path / "does-not-exist.exe"
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f'''import os
os.startfile({str(missing_target)!r})
''',
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    events = _read_access_events(result.access_log_path)
    assert any(event["decision"] == "deny" and event["event"].startswith("os.startfile") for event in events)


@pytest.mark.parametrize(
    ("source_template", "denied_event", "created_name"),
    [
        ("import os\nos.listdir({outside!r})\n", "os.listdir", None),
        ("import os\nos.mkdir({outside!r})\n", "os.mkdir", "outside-created"),
    ],
    ids=("directory-read", "directory-write"),
)
def test_restricted_runtime_denies_directory_operations_outside_allowlist(
    tmp_path, source_template, denied_event, created_name
):
    from unified_autoresearch.runtime.runner import run_candidate

    outside = tmp_path / (created_name or "outside-readable")
    if created_name is None:
        outside.mkdir()
    descriptor, layout = _prepare_prediction_run(
        tmp_path, source_template.format(outside=str(outside))
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    events = _read_access_events(result.access_log_path)
    assert any(event["decision"] == "deny" and event["event"] == denied_event for event in events)
    if created_name is not None:
        assert not outside.exists()


def test_restricted_runtime_rejects_zero_exit_without_required_output_and_records_result(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    descriptor, layout = _prepare_prediction_run(tmp_path, "pass\n")

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.process_exit_code == 0
    assert result.status == "contract_failure"
    recorded = json.loads(result.result_path.read_text(encoding="utf-8"))
    assert recorded["candidate_id"] == descriptor.candidate_id
    assert recorded["process_exit_code"] == 0
    assert recorded["normalized_exit_code"] == 2
    assert recorded["required_outputs_complete"] is False


def test_restricted_runtime_standardizes_unknown_exit_status_and_records_it(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    descriptor, layout = _prepare_prediction_run(tmp_path, "raise SystemExit(7)\n")

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 1
    assert result.process_exit_code == 7
    assert result.status == "runtime_failure"
    recorded = json.loads(result.result_path.read_text(encoding="utf-8"))
    assert recorded["process_exit_code"] == 7
    assert recorded["normalized_exit_code"] == 1


@pytest.mark.parametrize("artifact_kind", ["directory", "plain-text", "missing-columns"])
def test_restricted_runtime_rejects_invalid_prediction_artifact(tmp_path, artifact_kind):
    from unified_autoresearch.runtime.runner import run_candidate

    if artifact_kind == "directory":
        operation = "target.mkdir()"
    elif artifact_kind == "plain-text":
        operation = "target.write_text('not parquet', encoding='utf-8')"
    else:
        operation = f"target.write_bytes({_prediction_parquet_bytes(required_columns=False)!r})"
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f'''import os
from pathlib import Path
target = Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet"
{operation}
''',
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"


def test_restricted_runtime_rejects_undeclared_top_level_output(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f'''import os
from pathlib import Path
root = Path(os.environ["UNIFIED_OUTPUT_ROOT"])
(root / "predictions.parquet").write_bytes({_prediction_parquet_bytes()!r})
(root / "undeclared-extra.txt").write_text("extra", encoding="utf-8")
''',
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"


def test_restricted_runtime_promotes_valid_checkpoint_on_controlled_stop(tmp_path):
    from unified_autoresearch.runtime.checkpoints import verify_checkpoint
    from unified_autoresearch.runtime.control import request_controlled_stop
    from unified_autoresearch.runtime.runner import run_candidate

    payload = b"checkpoint-state"
    payload_digest = __import__("hashlib").sha256(payload).hexdigest()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f"""import json, os
from pathlib import Path
stop_request = Path(os.environ["UNIFIED_STOP_REQUEST"])
assert json.loads(stop_request.read_text(encoding="utf-8"))["request_id"] == "stop-0001"
root = Path(os.environ["UNIFIED_CHECKPOINT_STAGING_ROOT"])
(root / "model.bin").write_bytes({payload!r})
request = {{
    "schema_version": "checkpoint_request_v1",
    "checkpoint_id": "checkpoint-0001",
    "candidate_id": "runtime-candidate-001",
    "mode": "predict",
    "parent_checkpoint_id": None,
    "files": {{"model.bin": {payload_digest!r}}},
}}
(root / "CHECKPOINT_REQUEST.json").write_text(json.dumps(request, sort_keys=True), encoding="utf-8")
raise SystemExit(75)
""",
        )

    request_controlled_stop(layout.control_root, request_id="stop-0001", reason="test controlled stop")

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 75
    assert result.process_exit_code == 75
    assert result.status == "checkpointed"
    assert result.checkpoint_path == layout.checkpoints_root / "checkpoint-0001"
    checkpoint = verify_checkpoint(result.checkpoint_path, expected_candidate_id=descriptor.candidate_id)
    assert checkpoint.mode == "predict"
    recorded = json.loads(result.result_path.read_text(encoding="utf-8"))
    assert recorded["checkpoint_id"] == "checkpoint-0001"
    assert recorded["checkpoint_root_sha256"] == checkpoint.root_sha256


def test_restricted_runtime_rejects_controlled_stop_without_valid_checkpoint(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    descriptor, layout = _prepare_prediction_run(tmp_path, "raise SystemExit(75)\n")

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.process_exit_code == 75
    assert result.status == "contract_failure"
    assert result.checkpoint_path is None
    assert list(layout.checkpoints_root.iterdir()) == []


def test_restricted_runtime_does_not_publish_checkpoint_for_another_candidate(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    payload = b"foreign-checkpoint"
    payload_digest = __import__("hashlib").sha256(payload).hexdigest()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f"""import json, os
from pathlib import Path
root = Path(os.environ["UNIFIED_CHECKPOINT_STAGING_ROOT"])
(root / "model.bin").write_bytes({payload!r})
request = {{
    "schema_version": "checkpoint_request_v1",
    "checkpoint_id": "foreign-checkpoint",
    "candidate_id": "another-candidate",
    "mode": "predict",
    "parent_checkpoint_id": None,
    "files": {{"model.bin": {payload_digest!r}}},
}}
(root / "CHECKPOINT_REQUEST.json").write_text(json.dumps(request, sort_keys=True), encoding="utf-8")
raise SystemExit(75)
""",
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    assert result.checkpoint_path is None
    assert list(layout.checkpoints_root.iterdir()) == []
    assert layout.checkpoint_staging_root.is_dir()


def test_restricted_runtime_mounts_verified_resume_checkpoint_read_only(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    checkpoint = _publish_resume_checkpoint(tmp_path)
    prediction_bytes = _prediction_parquet_bytes()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f"""import os
from pathlib import Path
resume = Path(os.environ["UNIFIED_RESUME_CHECKPOINT"])
payload = (resume / "model.bin").read_bytes()
assert payload == b"resume-state"
target = Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet"
target.write_bytes({prediction_bytes!r})
""",
    )

    result = run_candidate(
        descriptor=descriptor,
        layout=layout,
        mode="predict",
        resume_checkpoint=checkpoint.path,
    )

    assert result.exit_code == 0
    assert result.status == "succeeded"
    assert (layout.output_root / "predictions.parquet").read_bytes() == prediction_bytes
    assert result.resume_checkpoint_path == layout.root / "resume_checkpoint"
    assert (result.resume_checkpoint_path / "model.bin").stat().st_mode & stat.S_IWRITE == 0
    recorded = json.loads(result.result_path.read_text(encoding="utf-8"))
    assert recorded["resume_checkpoint_id"] == checkpoint.checkpoint_id
    assert recorded["resume_checkpoint_root_sha256"] == checkpoint.root_sha256


def test_restricted_runtime_rejects_missing_resume_reference_before_launch(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    descriptor, layout = _prepare_prediction_run(tmp_path, "raise AssertionError('must not run')\n")

    with pytest.raises(ValueError, match="checkpoint request is missing"):
        run_candidate(
            descriptor=descriptor,
            layout=layout,
            mode="predict",
            resume_checkpoint=tmp_path / "missing-checkpoint",
        )
    assert list(layout.log_root.iterdir()) == []


def test_restricted_runtime_rejects_tampered_resume_reference_before_launch(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    checkpoint = _publish_resume_checkpoint(tmp_path)
    payload = checkpoint.path / "model.bin"
    payload.chmod(stat.S_IREAD | stat.S_IWRITE)
    payload.write_bytes(b"tampered")
    descriptor, layout = _prepare_prediction_run(tmp_path, "raise AssertionError('must not run')\n")

    with pytest.raises(ValueError, match="checkpoint payload hash mismatch"):
        run_candidate(
            descriptor=descriptor,
            layout=layout,
            mode="predict",
            resume_checkpoint=checkpoint.path,
        )
    assert list(layout.log_root.iterdir()) == []


@pytest.mark.parametrize("operation", ["remove", "hardlink"], ids=("remove", "hardlink-bypass"))
def test_restricted_runtime_denies_non_open_file_mutations_outside_allowlist(tmp_path, operation):
    from unified_autoresearch.runtime.runner import run_candidate

    forbidden = tmp_path / "outside-source.txt"
    forbidden.write_text("outside-content", encoding="utf-8")
    if operation == "remove":
        source = f"""import os
os.remove({str(forbidden)!r})
"""
        denied_event = "os.remove"
    else:
        output_target = tmp_path / "run" / "outputs" / "predictions.parquet"
        source = f"""import os
os.link({str(forbidden)!r}, {str(output_target)!r})
"""
        denied_event = "os.link"
    descriptor, layout = _prepare_prediction_run(tmp_path, source)

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    events = _read_access_events(result.access_log_path)
    assert any(event["decision"] == "deny" and event["event"] == denied_event for event in events)
    assert forbidden.read_text(encoding="utf-8") == "outside-content"
    assert not (layout.output_root / "predictions.parquet").exists()


def test_restricted_runtime_allows_atomic_rename_entirely_inside_output_root(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    prediction_bytes = _prediction_parquet_bytes()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f"""import os
from pathlib import Path
root = Path(os.environ["UNIFIED_OUTPUT_ROOT"])
temporary = root / "predictions.parquet.tmp"
temporary.write_bytes({prediction_bytes!r})
os.replace(temporary, root / "predictions.parquet")
""",
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 0
    assert (layout.output_root / "predictions.parquet").read_bytes() == prediction_bytes


def test_restricted_runtime_denies_launch_when_current_capacity_does_not_fit_request(tmp_path):
    from unified_autoresearch.runtime.resources import ResourceCapacityError, ResourceSnapshot
    from unified_autoresearch.runtime.runner import run_candidate

    descriptor, layout = _prepare_prediction_run(tmp_path, "raise AssertionError('must not run')\n")

    with pytest.raises(ResourceCapacityError):
        run_candidate(
            descriptor=descriptor,
            layout=layout,
            mode="predict",
            resource_snapshot=ResourceSnapshot(
                available_cpu_cores=8,
                available_gpu_count=0,
                available_memory_gb=0.49,
                free_disk_gb=100.0,
            ),
        )

    preflight_path = layout.log_root / "resource-preflight.json"
    preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
    assert preflight["decision"] == "deny"
    assert preflight["memory_fit"] is False
    assert not (layout.log_root / "runtime-policy.json").exists()
    assert not (layout.log_root / "access.jsonl").exists()


@pytest.mark.parametrize(
    ("resource_overrides", "failed_fit"),
    [
        ({"cpu_cores": 9}, "cpu_fit"),
        ({"gpu_count": 1}, "gpu_fit"),
    ],
    ids=("cpu-capacity", "gpu-capacity"),
)
def test_restricted_runtime_denies_launch_when_requested_processors_do_not_fit(
    tmp_path, resource_overrides, failed_fit
):
    from unified_autoresearch.runtime.resources import ResourceCapacityError
    from unified_autoresearch.runtime.runner import run_candidate

    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        "raise AssertionError('must not run')\n",
        resource_overrides=resource_overrides,
    )

    with pytest.raises(ResourceCapacityError):
        run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    preflight = json.loads((layout.log_root / "resource-preflight.json").read_text(encoding="utf-8"))
    assert preflight["decision"] == "deny"
    assert preflight[failed_fit] is False
    assert not (layout.log_root / "runtime-policy.json").exists()
    assert not (layout.log_root / "access.jsonl").exists()


def test_restricted_runtime_publishes_process_ownership_when_a_monitor_is_declared(tmp_path):
    """A declared monitor need is now honoured by supervising the run, not by refusing it."""
    from unified_autoresearch.runtime.runner import run_candidate

    payload = _prediction_parquet_bytes()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        "import os, base64, time\n"
        "time.sleep(0.4)\n"
        f"data = base64.b64decode({__import__('base64').b64encode(payload).decode('ascii')!r})\n"
        "with open(os.path.join(os.environ['UNIFIED_OUTPUT_ROOT'], 'predictions.parquet'), 'wb') as stream:\n"
        "    stream.write(data)\n",
        resource_overrides={
            "independent_monitor_enabled": True,
            "monitor_reason": "variable multi-process workload",
        },
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict", monitor_sample_interval_seconds=0.05)

    assert result.status == "succeeded"
    target = json.loads((layout.control_root / "MONITOR_TARGET.json").read_text(encoding="utf-8"))
    assert set(target) == {
        "schema_version",
        "process_id",
        "create_time",
        "executable_path",
        "run_id",
        "declared_memory_budget_gb",
    }
    assert target["run_id"] == f"{descriptor.candidate_id}-predict"
    # The supervisor is handed the candidate's reserved envelope so it can stop only for danger
    # the candidate itself can relieve, never for external pressure it did not cause.
    assert target["declared_memory_budget_gb"] == pytest.approx(
        float(descriptor.resources["estimated_peak_memory_gb"])
        + float(descriptor.resources["memory_safety_reserve_gb"])
    )


def test_restricted_runtime_does_not_publish_resume_checkpoint_with_wrong_parent_reference(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    parent = _publish_resume_checkpoint(tmp_path)
    payload = b"resumed-state"
    payload_digest = __import__("hashlib").sha256(payload).hexdigest()
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f"""import json, os
from pathlib import Path
root = Path(os.environ["UNIFIED_CHECKPOINT_STAGING_ROOT"])
(root / "model.bin").write_bytes({payload!r})
request = {{
    "schema_version": "checkpoint_request_v1",
    "checkpoint_id": "checkpoint-after-resume",
    "candidate_id": "runtime-candidate-001",
    "mode": "predict",
    "parent_checkpoint_id": None,
    "files": {{"model.bin": {payload_digest!r}}},
}}
(root / "CHECKPOINT_REQUEST.json").write_text(json.dumps(request), encoding="utf-8")
raise SystemExit(75)
""",
    )

    result = run_candidate(
        descriptor=descriptor,
        layout=layout,
        mode="predict",
        resume_checkpoint=parent.path,
    )

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    assert result.checkpoint_path is None
    assert list(layout.checkpoints_root.iterdir()) == []
    assert layout.checkpoint_staging_root.is_dir()


@pytest.mark.skipif(os.name != "nt", reason="Windows raw handle bypass is Windows-specific")
def test_restricted_runtime_blocks_winapi_raw_handle_file_read_bypass(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    forbidden = tmp_path / "winapi-forbidden.txt"
    forbidden.write_text("raw-handle-secret", encoding="utf-8")
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f"""import _winapi, msvcrt, os
from pathlib import Path
handle = _winapi.CreateFile(
    {str(forbidden)!r},
    _winapi.GENERIC_READ,
    0,
    _winapi.NULL,
    _winapi.OPEN_EXISTING,
    0,
    _winapi.NULL,
)
descriptor = msvcrt.open_osfhandle(handle, os.O_RDONLY)
with os.fdopen(descriptor, "rb") as stream:
    payload = stream.read()
(Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet").write_bytes(payload)
""",
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    assert result.status == "contract_failure"
    events = _read_access_events(result.access_log_path)
    assert any(
        event["decision"] == "deny"
        and event["event"] == "import"
        and event.get("module") == "_winapi"
        for event in events
    )
    assert not (layout.output_root / "predictions.parquet").exists()


@pytest.mark.skipif(os.name != "nt", reason="Windows raw handle bypass is Windows-specific")
def test_candidate_cannot_mutate_bootstrap_globals_to_reenable_winapi(tmp_path):
    from unified_autoresearch.runtime.runner import run_candidate

    forbidden = tmp_path / "bootstrap-mutation-forbidden.txt"
    forbidden.write_text("bootstrap-global-secret", encoding="utf-8")
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        f"""import sys
sys.modules["__main__"].FORBIDDEN_IMPORTS = set()
import _winapi, msvcrt, os
from pathlib import Path
handle = _winapi.CreateFile(
    {str(forbidden)!r}, _winapi.GENERIC_READ, 0, _winapi.NULL, _winapi.OPEN_EXISTING, 0, _winapi.NULL
)
descriptor = msvcrt.open_osfhandle(handle, os.O_RDONLY)
with os.fdopen(descriptor, "rb") as stream:
    payload = stream.read()
(Path(os.environ["UNIFIED_OUTPUT_ROOT"]) / "predictions.parquet").write_bytes(payload)
""",
    )

    result = run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert result.exit_code == 2
    events = _read_access_events(result.access_log_path)
    assert any(event["decision"] == "deny" and event.get("module") == "_winapi" for event in events)
    assert not (layout.output_root / "predictions.parquet").exists()
