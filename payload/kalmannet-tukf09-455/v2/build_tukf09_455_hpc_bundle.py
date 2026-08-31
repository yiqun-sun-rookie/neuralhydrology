"""Build, inspect, and safely extract the TUKF09 455-basin HPC bundle.

The bundle is training-only.  It carries the immutable preflight, migrated
filter evidence, authorization, and local training admission, but deliberately
does not carry the local result tree or any CAMELS source file.  HPC launchers
are transport wrappers and are not added to the admitted executable set.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import gzip
from hashlib import sha256
from io import BytesIO
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import tarfile
from typing import Any, Mapping
import uuid


ROOT = Path(__file__).resolve().parents[1]
EXPERIMENT_ID = "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
EXPERIMENT_SLUG = "tukf09_455_basin_zero_validation_target_variance_revision_v1"
ARTIFACT_RELATIVE_ROOT = Path("artifacts") / EXPERIMENT_SLUG
TRAINING_ADMISSION_RELATIVE = (
    ARTIFACT_RELATIVE_ROOT / "training_admission" / "training_admission.json"
)
DEFAULT_BUNDLE_OUTPUT = ROOT / "artifacts" / "tukf09_455_hpc_bundle_v1"
ARCHIVE_NAME = f"{EXPERIMENT_SLUG}_formal_training.tar.gz"
INTERNAL_MANIFEST_NAME = "bundle_manifest.json"
INTERNAL_SCHEMA = "tukf09_455_training_hpc_bundle_manifest_v1"
OUTER_SCHEMA = "tukf09_455_training_hpc_archive_manifest_v1"
PURPOSE = "formal_training_only_no_formal_evaluation"
RUNTIME_MUTABLE_ROOTS = (
    "kalmannet/G:/github/pycharm/projects/neuralhydrology/data/camels_us",
    f"kalmannet/results/{EXPERIMENT_SLUG}",
)
LOCAL_FILTER_INSTALLATION_FINAL_RELATIVE = (
    "results/tukf09_455_basin_zero_validation_target_variance_revision_v1/"
    "control/filter_rebinding/independent/manifest.final.sha256.json"
)
LOCAL_FILTER_INSTALLATION_FINAL_SHA256 = (
    "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"
)

MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 64 * 1024 * 1024
MAX_MEMBER_COUNT = 4096
EXPECTED_ADMITTED_EXECUTABLE_COUNT = 30
EXPECTED_ADMITTED_TEST_COUNT = 12
EXPECTED_ARTIFACT_FILE_COUNT = 2751
EXPECTED_MEMBER_COUNT = 2807

CONFIG_RELATIVES = (
    "configs/tukf09_455_basin_zero_validation_target_variance_execution_v1.json",
    "configs/tukf09_455_basin_zero_validation_target_variance_filter_migration_v1.json",
    "configs/tukf09_455_basin_zero_validation_target_variance_formal_evaluation_v1.json",
    "configs/tukf09_455_basin_zero_validation_target_variance_formal_training_execution_v1.json",
    "configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_v1.json",
    "configs/tukf09_455_basin_zero_validation_target_variance_revision_v1.json",
)
HPC_WRAPPER_RELATIVES = (
    "hpc/tukf09_455_basin_revision/allocation_probe.slurm",
    "hpc/tukf09_455_basin_revision/probe_gpu.slurm",
    "hpc/tukf09_455_basin_revision/psutil-source.lock",
    "hpc/tukf09_455_basin_revision/runtime-binary.lock",
    "hpc/tukf09_455_basin_revision/stage_and_train.py",
    "hpc/tukf09_455_basin_revision/submit_training_gpu.slurm",
    "hpc/tukf09_455_basin_revision/verify_result.py",
)
BUILDER_RELATIVE = "scripts/build_tukf09_455_hpc_bundle.py"
NON_ADMITTED_WRAPPER_RELATIVES = (BUILDER_RELATIVE, *HPC_WRAPPER_RELATIVES)

ARTIFACT_TREES = {
    "preflight": "independent/manifest.final.sha256.json",
    "filter_migration_v1": "independent/manifest.final.sha256.json",
}
SINGLETON_ARTIFACTS = (
    "authorizations/all_scope_authorization.json",
    "training_admission/training_admission.json",
)


@dataclass(frozen=True)
class BundleManifest:
    archive_path: Path
    archive_sha256: str
    archive_size: int
    manifest_path: Path
    member_sha256: dict[str, str]


def _canonical_json_bytes(value: Any, *, trailing_line_feed: bool = True) -> bytes:
    content = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return content + (b"\n" if trailing_line_feed else b"")


def _display_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            allow_nan=False,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")


def _sha256_file(path: Path, *, chunk_size: int = 1024 * 1024) -> str:
    digest = sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(chunk_size), b""):
            digest.update(block)
    return digest.hexdigest()


def _read_json(path: Path, *, canonical: bool = False) -> dict[str, Any]:
    source = Path(path)
    raw = source.read_bytes()
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"invalid JSON: {source}") from exc
    if not isinstance(payload, dict):
        raise RuntimeError(f"JSON root must be an object: {source}")
    if canonical and raw != _canonical_json_bytes(payload):
        raise RuntimeError(f"JSON is not canonical: {source}")
    return payload


def _path_exists(path: Path) -> bool:
    return os.path.lexists(os.fspath(path))


def _absolute_io_path(path: Path, *, force_windows_long: bool = False) -> Path:
    absolute = os.path.abspath(os.fspath(path))
    if (
        os.name == "nt"
        and not absolute.startswith("\\\\?\\")
        and (force_windows_long or len(absolute) >= 240)
    ):
        absolute = "\\\\?\\" + absolute
    return Path(absolute)


def _is_reparse_point(path: Path) -> bool:
    status = path.lstat()
    attributes = int(getattr(status, "st_file_attributes", 0))
    reparse_flag = int(getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
    return stat.S_ISLNK(status.st_mode) or bool(attributes & reparse_flag)


def _require_regular_unlinked_file(path: Path, *, root: Path) -> Path:
    raw_candidate = os.path.abspath(os.fspath(path))
    force_long = raw_candidate.startswith("\\\\?\\") or len(raw_candidate) >= 240
    project_root = _absolute_io_path(root, force_windows_long=force_long)
    candidate = _absolute_io_path(path, force_windows_long=force_long)
    try:
        relative = candidate.relative_to(project_root)
    except ValueError as exc:
        raise ValueError(f"bundle source escapes project root: {path}") from exc
    current = project_root
    for part in relative.parts:
        current = current / part
        if _path_exists(current) and _is_reparse_point(current):
            raise ValueError(f"linked bundle source is forbidden: {current}")
    if not candidate.is_file() or candidate.is_symlink():
        raise FileNotFoundError(f"bundle source is not a regular file: {candidate}")
    if candidate.stat().st_nlink != 1:
        raise ValueError(f"hard-linked bundle source is forbidden: {candidate}")
    return candidate


def _safe_member_name(name: str) -> None:
    relative = PurePosixPath(name)
    if (
        not name
        or "\\" in name
        or "\x00" in name
        or relative.is_absolute()
        or relative.as_posix() != name
        or any(part in {"", ".", ".."} for part in relative.parts)
        or any(":" in part or part.endswith((" ", ".")) for part in relative.parts)
    ):
        raise ValueError(f"unsafe or noncanonical bundle member name: {name!r}")


def _archive_name(relative: str | Path) -> str:
    value = "kalmannet/" + Path(relative).as_posix()
    _safe_member_name(value)
    return value


def _forbidden_member(name: str) -> bool:
    parts = PurePosixPath(name).parts
    lowered = tuple(part.lower() for part in parts)
    if any(
        part in {".git", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"}
        for part in lowered
    ):
        return True
    if len(lowered) >= 2 and lowered[0] == "kalmannet" and lowered[1] in {
        "results",
        "data",
        "datasets",
        "inputs",
    }:
        return True
    if any(part in {"neural", "selection", "evaluation"} for part in lowered[:3]):
        return True
    if PurePosixPath(name).suffix.lower() in {".pt", ".pth", ".ckpt"}:
        return True
    return False


def _atomic_write_bytes(path: Path, content: bytes, *, refuse_different: bool) -> bool:
    destination = Path(path)
    if _path_exists(destination):
        if (
            refuse_different
            and destination.is_file()
            and not destination.is_symlink()
            and destination.read_bytes() == content
        ):
            return True
        if refuse_different:
            raise RuntimeError(f"refusing to replace a different file: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(
        destination.name + f".tmp-{os.getpid()}-{uuid.uuid4().hex}"
    )
    try:
        with temporary.open("xb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        if _path_exists(destination):
            raise RuntimeError(f"destination appeared before publication: {destination}")
        os.replace(temporary, destination)
    finally:
        if _path_exists(temporary):
            temporary.unlink()
    return False


def _regular_tree_files(directory: Path, *, root: Path) -> dict[str, Path]:
    source_root = _absolute_io_path(directory, force_windows_long=(os.name == "nt"))
    if not source_root.is_dir() or _is_reparse_point(source_root):
        raise RuntimeError(f"artifact tree is absent or linked: {source_root}")
    records: dict[str, Path] = {}
    for current_text, directory_names, file_names in os.walk(
        source_root, topdown=True, followlinks=False
    ):
        current = Path(current_text)
        for directory_name in list(directory_names):
            candidate = current / directory_name
            if _is_reparse_point(candidate):
                raise ValueError(f"linked artifact directory is forbidden: {candidate}")
        for file_name in file_names:
            candidate = _require_regular_unlinked_file(current / file_name, root=root)
            relative = candidate.relative_to(source_root).as_posix()
            _safe_member_name(relative)
            records[relative] = candidate
    return dict(sorted(records.items()))


def _verified_manifest_tree(
    directory: Path,
    *,
    final_manifest_relative: str,
    root: Path,
) -> dict[str, Path]:
    sources = _regular_tree_files(directory, root=root)
    if final_manifest_relative not in sources:
        raise RuntimeError(f"independent final manifest is absent: {directory}")
    final = _read_json(sources[final_manifest_relative], canonical=True)
    records = final.get("files")
    if (
        final.get("experiment_id") != EXPERIMENT_ID
        or not isinstance(records, dict)
        or final.get("file_count") != len(records)
        or set(sources) != set(records) | {final_manifest_relative}
    ):
        raise RuntimeError(f"artifact tree differs from its independent final manifest: {directory}")
    for relative, record in records.items():
        _safe_member_name(relative)
        source = sources.get(relative)
        if (
            source is None
            or record
            != {
                "sha256": _sha256_file(source),
                "size_bytes": source.stat().st_size,
            }
        ):
            raise RuntimeError(f"artifact hash mismatch: {directory / relative}")
    return sources


def _load_and_verify_training_admission(root: Path) -> dict[str, Any]:
    project_root = Path(root)
    admission_path = _require_regular_unlinked_file(
        project_root / TRAINING_ADMISSION_RELATIVE, root=project_root
    )
    admission = _read_json(admission_path, canonical=True)
    unsigned = dict(admission)
    stored = unsigned.pop("training_admission_record_sha256", None)
    if stored != sha256(_canonical_json_bytes(unsigned)).hexdigest():
        raise RuntimeError("training admission record hash mismatch")
    if (
        admission.get("schema_version") != "tukf09_455_training_admission_v1"
        or admission.get("experiment_id") != EXPERIMENT_ID
        or admission.get("formal_evaluation_authorized") is not False
        or admission.get("phase_scope", {}).get("formal_evaluation_access_admitted")
        is not False
        or admission.get("evaluation_identity", {}).get("arrays_loaded") is not False
        or admission.get("access_ledger")
        != {
            "evaluation_array_reads": 0,
            "evaluation_metrics": 0,
            "evaluation_outputs": 0,
            "evaluation_predictions": 0,
        }
    ):
        raise PermissionError("training admission identity or evaluation hold changed")

    executables = admission.get("executables")
    tests = admission.get("test_evidence", {}).get("pytest_file_records")
    if (
        not isinstance(executables, dict)
        or len(executables) != EXPECTED_ADMITTED_EXECUTABLE_COUNT
        or not isinstance(tests, dict)
        or len(tests) != EXPECTED_ADMITTED_TEST_COUNT
        or admission.get("test_evidence", {}).get("result") != "PASS"
    ):
        raise RuntimeError("admitted executable or test inventory changed")
    for label, records in (("executable", executables), ("test", tests)):
        for relative, record in records.items():
            _safe_member_name(relative)
            source = _require_regular_unlinked_file(project_root / relative, root=project_root)
            if record != {
                "sha256": _sha256_file(source),
                "size_bytes": source.stat().st_size,
            }:
                raise RuntimeError(f"admitted {label} hash mismatch: {relative}")

    execution = admission.get("execution_config", {})
    execution_path = _require_regular_unlinked_file(
        project_root / str(execution.get("path", "")), root=project_root
    )
    if execution.get("sha256") != _sha256_file(execution_path):
        raise RuntimeError("admitted execution config hash mismatch")
    return admission


def _validate_config_anchors(root: Path, admission: Mapping[str, Any]) -> None:
    project_root = Path(root)
    config_sources = {
        relative: _require_regular_unlinked_file(project_root / relative, root=project_root)
        for relative in CONFIG_RELATIVES
    }
    scientific = admission.get("scientific_contract", {})
    scientific_path = str(scientific.get("path", ""))
    if (
        scientific_path not in config_sources
        or scientific.get("sha256") != _sha256_file(config_sources[scientific_path])
    ):
        raise RuntimeError("scientific contract hash changed")
    authorization_path = project_root / ARTIFACT_RELATIVE_ROOT / (
        "authorizations/all_scope_authorization.json"
    )
    authorization = _read_json(authorization_path, canonical=True)
    if _sha256_file(authorization_path) != admission.get("authorization", {}).get("file_sha256"):
        raise RuntimeError("all-scope authorization file hash changed")
    anchors = authorization.get("frozen_inputs")
    if not isinstance(anchors, dict):
        raise RuntimeError("all-scope authorization frozen inputs are absent")
    for record in anchors.values():
        relative = str(record.get("path", ""))
        source = _require_regular_unlinked_file(project_root / relative, root=project_root)
        if record != {
            "path": relative,
            "sha256": _sha256_file(source),
            "size_bytes": source.stat().st_size,
        }:
            raise RuntimeError(f"authorization frozen input changed: {relative}")
    preflight_execution = (
        project_root / ARTIFACT_RELATIVE_ROOT / "preflight/execution_config.snapshot.json"
    )
    if preflight_execution.read_bytes() != config_sources[CONFIG_RELATIVES[0]].read_bytes():
        raise RuntimeError("preflight execution config differs from its sealed snapshot")
    hpc = _read_json(config_sources[CONFIG_RELATIVES[4]])
    hpc_identity = hpc.get("scientific_identity", {})
    hpc_bundle = hpc.get("bundle_contract", {})
    admission_path = project_root / TRAINING_ADMISSION_RELATIVE
    formal_training_relative = CONFIG_RELATIVES[3]
    formal_training_path = config_sources[formal_training_relative]
    formal_training_record = hpc_identity.get("formal_training_execution", {})
    authorization_relative = (
        ARTIFACT_RELATIVE_ROOT / "authorizations" / "all_scope_authorization.json"
    ).as_posix()
    authorization_record = hpc_identity.get("all_scope_authorization", {})
    local_filter_record = hpc_identity.get("local_filter_installation_final_manifest", {})
    local_filter_path = project_root / LOCAL_FILTER_INSTALLATION_FINAL_RELATIVE
    if (
        hpc.get("schema_version") != "tukf09_455_basin_hpc_execution_v1"
        or hpc.get("experiment_id") != EXPERIMENT_ID
        or hpc.get("execution_route", {}).get("formal_evaluation_access") is not False
        or hpc_bundle.get("manifest_name") != INTERNAL_MANIFEST_NAME
        or hpc_bundle.get("schema_version") != INTERNAL_SCHEMA
        or hpc_bundle.get("purpose") != PURPOSE
        or hpc_bundle.get("project_directory_name") != "kalmannet"
        or hpc_bundle.get("admitted_executable_count")
        != EXPECTED_ADMITTED_EXECUTABLE_COUNT
        or hpc_bundle.get("admitted_test_count") != EXPECTED_ADMITTED_TEST_COUNT
        or hpc_bundle.get("required_non_admitted_wrappers")
        != [_archive_name(relative) for relative in HPC_WRAPPER_RELATIVES]
        or hpc_identity.get("scientific_contract", {}).get("sha256")
        != admission.get("scientific_contract_sha256")
        or formal_training_record
        != {
            "path": formal_training_relative,
            "sha256": _sha256_file(formal_training_path),
        }
        or authorization_record
        != {
            "path": authorization_relative,
            "sha256": _sha256_file(authorization_path),
        }
        or hpc_identity.get("independent_preflight_final_manifest", {}).get("sha256")
        != admission.get("preflight_final_manifest_sha256")
        or hpc_identity.get("filter_migration_final_manifest", {}).get("sha256")
        != admission.get("filter_migration_final_manifest", {}).get("sha256")
        or hpc_identity.get("original_training_admission", {}).get("file_sha256")
        != _sha256_file(admission_path)
        or hpc_identity.get("original_training_admission", {}).get("record_sha256")
        != admission.get("training_admission_record_sha256")
        or local_filter_record
        != {
            "path": LOCAL_FILTER_INSTALLATION_FINAL_RELATIVE,
            "sha256": LOCAL_FILTER_INSTALLATION_FINAL_SHA256,
        }
    ):
        raise RuntimeError("HPC technical execution config changed its frozen scope")
    if _path_exists(local_filter_path) and _sha256_file(
        _require_regular_unlinked_file(local_filter_path, root=project_root)
    ) != LOCAL_FILTER_INSTALLATION_FINAL_SHA256:
        raise RuntimeError("local filter installation final manifest changed")


def bundle_member_sources(*, root: Path = ROOT) -> dict[str, Path]:
    """Return the exact source allowlist after verifying all frozen anchors."""

    project_root = Path(root)
    admission = _load_and_verify_training_admission(project_root)
    _validate_config_anchors(project_root, admission)
    members: dict[str, Path] = {}

    def add(relative: str | Path, source: Path | None = None) -> None:
        relative_text = Path(relative).as_posix()
        name = _archive_name(relative_text)
        if name in members:
            raise RuntimeError(f"duplicate bundle member: {name}")
        if _forbidden_member(name):
            raise RuntimeError(f"forbidden bundle member: {name}")
        members[name] = _require_regular_unlinked_file(
            source if source is not None else project_root / relative_text,
            root=project_root,
        )

    for relative in admission["executables"]:
        add(relative)
    for relative in admission["test_evidence"]["pytest_file_records"]:
        add(relative)
    for relative in CONFIG_RELATIVES:
        add(relative)
    for tree_name, final_relative in ARTIFACT_TREES.items():
        tree_root = project_root / ARTIFACT_RELATIVE_ROOT / tree_name
        sources = _verified_manifest_tree(
            tree_root,
            final_manifest_relative=final_relative,
            root=project_root,
        )
        for relative, source in sources.items():
            add(ARTIFACT_RELATIVE_ROOT / tree_name / Path(relative), source)
    for relative in SINGLETON_ARTIFACTS:
        add(ARTIFACT_RELATIVE_ROOT / Path(relative))
    for relative in NON_ADMITTED_WRAPPER_RELATIVES:
        add(relative)

    if len(members) != EXPECTED_MEMBER_COUNT:
        raise RuntimeError(
            f"HPC bundle member count changed: {len(members)} != {EXPECTED_MEMBER_COUNT}"
        )
    return dict(sorted(members.items()))


def _manifest_metadata(
    admission: Mapping[str, Any],
    member_hashes: Mapping[str, str],
    member_sizes: Mapping[str, int],
) -> dict[str, Any]:
    artifact_prefix = _archive_name(ARTIFACT_RELATIVE_ROOT) + "/"
    artifact_count = sum(name.startswith(artifact_prefix) for name in member_hashes)
    if artifact_count != EXPECTED_ARTIFACT_FILE_COUNT:
        raise RuntimeError("complete revised artifact inventory changed")
    return {
        "experiment_id": EXPERIMENT_ID,
        "purpose": PURPOSE,
        "member_count": len(member_hashes),
        "admitted_executable_count": len(admission["executables"]),
        "admitted_test_count": len(
            admission["test_evidence"]["pytest_file_records"]
        ),
        "artifact_file_count": artifact_count,
        "config_file_count": len(CONFIG_RELATIVES),
        "non_admitted_wrapper_count": len(NON_ADMITTED_WRAPPER_RELATIVES),
        "non_admitted_wrappers": [
            _archive_name(relative) for relative in NON_ADMITTED_WRAPPER_RELATIVES
        ],
        "local_results_file_count": 0,
        "camels_raw_file_count": 0,
        "neural_checkpoint_count": 0,
        "formal_selection_output_count": 0,
        "formal_evaluation_output_count": 0,
        "training_admission": {
            "path": _archive_name(TRAINING_ADMISSION_RELATIVE),
            "sha256": member_hashes[_archive_name(TRAINING_ADMISSION_RELATIVE)],
            "record_sha256": admission["training_admission_record_sha256"],
        },
        "scientific_contract_sha256": admission["scientific_contract_sha256"],
        "preflight_final_manifest_sha256": admission[
            "preflight_final_manifest_sha256"
        ],
        "filter_migration_final_manifest_sha256": admission[
            "filter_migration_final_manifest"
        ]["sha256"],
        "member_sha256": dict(sorted(member_hashes.items())),
        "member_size": dict(sorted(member_sizes.items())),
    }


def _validate_archived_admission_members(
    admission: Mapping[str, Any],
    hashes: Mapping[str, str],
    sizes: Mapping[str, int],
) -> None:
    for records in (
        admission["executables"],
        admission["test_evidence"]["pytest_file_records"],
    ):
        for relative, record in records.items():
            name = _archive_name(relative)
            if hashes.get(name) != record["sha256"] or sizes.get(name) != record["size_bytes"]:
                raise RuntimeError(f"archived admitted member changed during build: {relative}")


def _archive_bytes(
    members: Mapping[str, Path], admission: Mapping[str, Any]
) -> tuple[bytes, dict[str, str], dict[str, int], dict[str, Any]]:
    payloads = {name: Path(path).read_bytes() for name, path in members.items()}
    member_hashes = {
        name: sha256(content).hexdigest() for name, content in sorted(payloads.items())
    }
    member_sizes = {name: len(content) for name, content in sorted(payloads.items())}
    _validate_archived_admission_members(admission, member_hashes, member_sizes)
    metadata = _manifest_metadata(admission, member_hashes, member_sizes)
    internal = {"schema_version": INTERNAL_SCHEMA, **metadata}
    payloads[INTERNAL_MANIFEST_NAME] = _display_json_bytes(internal)

    total_size = sum(len(content) for content in payloads.values())
    if total_size > MAX_UNCOMPRESSED_BYTES:
        raise RuntimeError("HPC bundle exceeds the uncompressed safety limit")
    raw = BytesIO()
    with gzip.GzipFile(
        fileobj=raw, mode="wb", filename="", mtime=0, compresslevel=9
    ) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
            for name in sorted(payloads):
                content = payloads[name]
                info = tarfile.TarInfo(name=name)
                info.size = len(content)
                info.mtime = 0
                info.uid = 0
                info.gid = 0
                info.uname = ""
                info.gname = ""
                info.mode = 0o755 if name.endswith((".slurm", ".sh")) else 0o644
                archive.addfile(info, BytesIO(content))
    return raw.getvalue(), member_hashes, member_sizes, metadata


def _inspect_archive(archive_path: Path) -> tuple[dict[str, bytes], dict[str, Any]]:
    source = Path(archive_path)
    if not source.is_file() or source.is_symlink():
        raise FileNotFoundError(source)
    if source.stat().st_size > MAX_ARCHIVE_BYTES:
        raise RuntimeError("HPC archive exceeds the compressed safety limit")
    payloads: dict[str, bytes] = {}
    with tarfile.open(source, "r:gz") as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        if (
            len(members) > MAX_MEMBER_COUNT
            or names != sorted(names)
            or len(names) != len(set(names))
        ):
            raise RuntimeError("archive member count, order, or uniqueness differs")
        total_size = 0
        for member in members:
            _safe_member_name(member.name)
            if (
                member.type not in {tarfile.REGTYPE, tarfile.AREGTYPE}
                or not member.isfile()
                or member.issym()
                or member.islnk()
                or member.size < 0
            ):
                raise RuntimeError(f"archive contains a non-regular member: {member.name}")
            total_size += member.size
            if total_size > MAX_UNCOMPRESSED_BYTES:
                raise RuntimeError("archive exceeds the uncompressed safety limit")
        for member in members:
            stream = archive.extractfile(member)
            if stream is None:
                raise RuntimeError(f"cannot read archive member: {member.name}")
            content = stream.read()
            if len(content) != member.size:
                raise RuntimeError(f"archive member length mismatch: {member.name}")
            payloads[member.name] = content

    if INTERNAL_MANIFEST_NAME not in payloads:
        raise RuntimeError("archive has no internal bundle manifest")
    try:
        internal = json.loads(payloads[INTERNAL_MANIFEST_NAME].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("archive internal manifest is invalid") from exc
    if not isinstance(internal, dict):
        raise RuntimeError("archive internal manifest root differs")
    hashes = internal.get("member_sha256")
    sizes = internal.get("member_size")
    if (
        internal.get("schema_version") != INTERNAL_SCHEMA
        or internal.get("experiment_id") != EXPERIMENT_ID
        or internal.get("purpose") != PURPOSE
        or not isinstance(hashes, dict)
        or not isinstance(sizes, dict)
        or set(payloads) != set(hashes) | {INTERNAL_MANIFEST_NAME}
        or internal.get("member_count") != len(hashes)
        or len(hashes) != EXPECTED_MEMBER_COUNT
    ):
        raise RuntimeError("archive members or internal manifest identity differ")
    for name, expected in hashes.items():
        _safe_member_name(name)
        if (
            _forbidden_member(name)
            or sha256(payloads[name]).hexdigest() != expected
            or len(payloads[name]) != sizes.get(name)
        ):
            raise RuntimeError(f"archive member hash, size, or policy mismatch: {name}")
    return payloads, internal


def build_bundle(
    destination: Path = DEFAULT_BUNDLE_OUTPUT, *, root: Path = ROOT
) -> BundleManifest:
    project_root = Path(root)
    admission = _load_and_verify_training_admission(project_root)
    members = bundle_member_sources(root=project_root)
    archive_bytes, hashes, sizes, metadata = _archive_bytes(members, admission)
    if len(archive_bytes) > MAX_ARCHIVE_BYTES:
        raise RuntimeError("HPC bundle exceeds the compressed safety limit")
    output = Path(destination)
    archive_path = output / ARCHIVE_NAME
    archive_hash = sha256(archive_bytes).hexdigest()
    outer = {
        "schema_version": OUTER_SCHEMA,
        "archive_name": ARCHIVE_NAME,
        "archive_sha256": archive_hash,
        "archive_size": len(archive_bytes),
        **metadata,
    }
    _atomic_write_bytes(archive_path, archive_bytes, refuse_different=True)
    manifest_path = output / "bundle_manifest.sha256.json"
    _atomic_write_bytes(manifest_path, _display_json_bytes(outer), refuse_different=True)
    payloads, internal = _inspect_archive(archive_path)
    if (
        internal["member_sha256"] != hashes
        or internal["member_size"] != sizes
        or len(payloads) != len(hashes) + 1
    ):
        raise RuntimeError("archive post-write verification differs")
    return BundleManifest(
        archive_path=archive_path,
        archive_sha256=archive_hash,
        archive_size=len(archive_bytes),
        manifest_path=manifest_path,
        member_sha256=hashes,
    )


def _extracted_inventory(root: Path) -> set[str]:
    names: set[str] = set()
    for current_text, directory_names, file_names in os.walk(
        root, topdown=True, followlinks=False
    ):
        current = Path(current_text)
        for directory_name in list(directory_names):
            candidate = current / directory_name
            if _is_reparse_point(candidate):
                raise RuntimeError(f"linked extracted directory is forbidden: {candidate}")
        for file_name in file_names:
            candidate = current / file_name
            if _is_reparse_point(candidate) or not candidate.is_file():
                raise RuntimeError(f"linked or irregular extracted file is forbidden: {candidate}")
            relative = candidate.relative_to(root).as_posix()
            _safe_member_name(relative)
            names.add(relative)
    return names


def _is_same_or_descendant(
    relative: PurePosixPath, parent: PurePosixPath
) -> bool:
    return relative.parts[: len(parent.parts)] == parent.parts


def _runtime_relative_path(relative: PurePosixPath) -> str:
    """Return a canonical runtime path, permitting only the sealed ``G:`` component."""

    name = relative.as_posix()
    colon_parts = [
        (index, part) for index, part in enumerate(relative.parts) if ":" in part
    ]
    if (
        not name
        or name == "."
        or "\\" in name
        or "\x00" in name
        or relative.is_absolute()
        or any(part in {"", ".", ".."} for part in relative.parts)
        or any(part.endswith((" ", ".")) for part in relative.parts)
        or colon_parts not in ([], [(1, "G:")])
        or (colon_parts and relative.parts[0] != "kalmannet")
    ):
        raise RuntimeError(f"unsafe or noncanonical runtime path: {name!r}")
    return name


def _runtime_extracted_inventory(
    root: Path, expected_names: set[str]
) -> dict[str, int]:
    """Audit an extracted runtime tree without trusting mutable-tree contents."""

    mutable_roots = tuple(PurePosixPath(name) for name in RUNTIME_MUTABLE_ROOTS)
    expected_directories: set[str] = set()
    for name in expected_names:
        for parent in PurePosixPath(name).parents:
            if parent.as_posix() != ".":
                expected_directories.add(parent.as_posix())
    mutable_ancestors = {
        parent.as_posix()
        for mutable_root in mutable_roots
        for parent in mutable_root.parents
        if parent.as_posix() != "."
    }
    frozen_files_seen: set[str] = set()
    mutable_file_count = 0
    mutable_directory_count = 0

    def fail_walk(error: OSError) -> None:
        raise RuntimeError(f"cannot inspect extracted runtime tree: {error}") from error

    for current_text, directory_names, file_names in os.walk(
        root, topdown=True, followlinks=False, onerror=fail_walk
    ):
        current = Path(current_text)
        for directory_name in list(directory_names):
            candidate = current / directory_name
            if _is_reparse_point(candidate) or not candidate.is_dir():
                raise RuntimeError(
                    f"linked or irregular runtime directory is forbidden: {candidate}"
                )
            relative = PurePosixPath(candidate.relative_to(root).as_posix())
            relative_name = _runtime_relative_path(relative)
            within_mutable = any(
                _is_same_or_descendant(relative, mutable_root)
                for mutable_root in mutable_roots
            )
            if within_mutable:
                mutable_directory_count += 1
            elif (
                relative_name not in expected_directories
                and relative_name not in mutable_ancestors
            ):
                raise RuntimeError(
                    f"unexpected runtime directory outside mutable roots: {relative_name}"
                )
        for file_name in file_names:
            candidate = current / file_name
            if _is_reparse_point(candidate) or not candidate.is_file():
                raise RuntimeError(
                    f"linked or irregular runtime file is forbidden: {candidate}"
                )
            status = candidate.stat()
            if status.st_nlink != 1:
                raise RuntimeError(f"hard-linked runtime file is forbidden: {candidate}")
            relative = PurePosixPath(candidate.relative_to(root).as_posix())
            relative_name = _runtime_relative_path(relative)
            if relative_name in expected_names:
                frozen_files_seen.add(relative_name)
            elif any(
                _is_same_or_descendant(relative, mutable_root)
                for mutable_root in mutable_roots
            ):
                mutable_file_count += 1
            else:
                raise RuntimeError(
                    f"unexpected runtime file outside mutable roots: {relative_name}"
                )
    if frozen_files_seen != expected_names:
        raise RuntimeError("extracted runtime frozen file inventory differs")
    return {
        "mutable_file_count": mutable_file_count,
        "mutable_directory_count": mutable_directory_count,
    }


def verify_extracted_bundle(destination: Path) -> dict[str, Any]:
    root = _absolute_io_path(destination, force_windows_long=(os.name == "nt"))
    if not root.is_dir() or root.is_symlink():
        raise RuntimeError("extracted bundle is absent or linked")
    manifest_path = root / INTERNAL_MANIFEST_NAME
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise RuntimeError("extracted internal manifest is absent or linked")
    manifest = _read_json(manifest_path)
    hashes = manifest.get("member_sha256")
    sizes = manifest.get("member_size")
    if (
        manifest.get("schema_version") != INTERNAL_SCHEMA
        or manifest.get("experiment_id") != EXPERIMENT_ID
        or manifest.get("purpose") != PURPOSE
        or manifest.get("admitted_executable_count")
        != EXPECTED_ADMITTED_EXECUTABLE_COUNT
        or manifest.get("admitted_test_count") != EXPECTED_ADMITTED_TEST_COUNT
        or manifest.get("artifact_file_count") != EXPECTED_ARTIFACT_FILE_COUNT
        or manifest.get("local_results_file_count") != 0
        or manifest.get("camels_raw_file_count") != 0
        or manifest.get("neural_checkpoint_count") != 0
        or manifest.get("formal_selection_output_count") != 0
        or manifest.get("formal_evaluation_output_count") != 0
        or not isinstance(hashes, dict)
        or not isinstance(sizes, dict)
        or len(hashes) != EXPECTED_MEMBER_COUNT
    ):
        raise RuntimeError("extracted bundle manifest identity or scope differs")
    expected_names = set(hashes) | {INTERNAL_MANIFEST_NAME}
    if _extracted_inventory(root) != expected_names:
        raise RuntimeError("extracted bundle file inventory differs")
    expected_sources = bundle_member_sources(root=root / "kalmannet")
    if set(expected_sources) != set(hashes):
        raise RuntimeError("extracted bundle allowlist differs from frozen sources")
    for name, expected in hashes.items():
        _safe_member_name(name)
        path = root.joinpath(*PurePosixPath(name).parts)
        if (
            _forbidden_member(name)
            or not path.is_file()
            or path.is_symlink()
            or path.stat().st_nlink != 1
            or _sha256_file(path) != expected
            or path.stat().st_size != sizes.get(name)
        ):
            raise RuntimeError(f"extracted bundle member mismatch: {name}")
    return {
        "status": "TUKF09_455_HPC_BUNDLE_VERIFIED",
        "experiment_id": EXPERIMENT_ID,
        "member_count": len(hashes),
        "admitted_executable_count": EXPECTED_ADMITTED_EXECUTABLE_COUNT,
        "admitted_test_count": EXPECTED_ADMITTED_TEST_COUNT,
        "artifact_file_count": EXPECTED_ARTIFACT_FILE_COUNT,
        "formal_evaluation_output_count": 0,
    }


def verify_runtime_bundle(destination: Path) -> dict[str, Any]:
    """Verify frozen members while allowing only the two declared runtime trees."""

    root = _absolute_io_path(destination, force_windows_long=(os.name == "nt"))
    if (
        not root.is_dir()
        or root.is_symlink()
        or _is_reparse_point(root)
    ):
        raise RuntimeError("runtime bundle is absent or linked")
    manifest_path = root / INTERNAL_MANIFEST_NAME
    if (
        not manifest_path.is_file()
        or manifest_path.is_symlink()
        or _is_reparse_point(manifest_path)
        or manifest_path.stat().st_nlink != 1
    ):
        raise RuntimeError("runtime internal manifest is absent or linked")
    manifest = _read_json(manifest_path)
    hashes = manifest.get("member_sha256")
    sizes = manifest.get("member_size")
    if (
        manifest.get("schema_version") != INTERNAL_SCHEMA
        or manifest.get("experiment_id") != EXPERIMENT_ID
        or manifest.get("purpose") != PURPOSE
        or manifest.get("admitted_executable_count")
        != EXPECTED_ADMITTED_EXECUTABLE_COUNT
        or manifest.get("admitted_test_count") != EXPECTED_ADMITTED_TEST_COUNT
        or manifest.get("artifact_file_count") != EXPECTED_ARTIFACT_FILE_COUNT
        or manifest.get("local_results_file_count") != 0
        or manifest.get("camels_raw_file_count") != 0
        or manifest.get("neural_checkpoint_count") != 0
        or manifest.get("formal_selection_output_count") != 0
        or manifest.get("formal_evaluation_output_count") != 0
        or not isinstance(hashes, dict)
        or not isinstance(sizes, dict)
        or len(hashes) != EXPECTED_MEMBER_COUNT
    ):
        raise RuntimeError("runtime bundle manifest identity or scope differs")
    expected_names = set(hashes) | {INTERNAL_MANIFEST_NAME}
    runtime_counts = _runtime_extracted_inventory(root, expected_names)
    expected_sources = bundle_member_sources(root=root / "kalmannet")
    if set(expected_sources) != set(hashes):
        raise RuntimeError("runtime bundle allowlist differs from frozen sources")
    for name, expected in hashes.items():
        _safe_member_name(name)
        path = root.joinpath(*PurePosixPath(name).parts)
        if (
            _forbidden_member(name)
            or not path.is_file()
            or path.is_symlink()
            or _is_reparse_point(path)
            or path.stat().st_nlink != 1
            or _sha256_file(path) != expected
            or path.stat().st_size != sizes.get(name)
        ):
            raise RuntimeError(f"runtime bundle member mismatch: {name}")
    return {
        "status": "TUKF09_455_HPC_RUNTIME_BUNDLE_VERIFIED",
        "experiment_id": EXPERIMENT_ID,
        "member_count": len(hashes),
        "admitted_executable_count": EXPECTED_ADMITTED_EXECUTABLE_COUNT,
        "admitted_test_count": EXPECTED_ADMITTED_TEST_COUNT,
        "artifact_file_count": EXPECTED_ARTIFACT_FILE_COUNT,
        "formal_evaluation_output_count": 0,
        "mutable_roots": list(RUNTIME_MUTABLE_ROOTS),
        **runtime_counts,
    }


def extract_bundle(archive_path: Path, destination: Path) -> dict[str, Any]:
    archive = Path(archive_path)
    payloads, internal = _inspect_archive(archive)
    target = _absolute_io_path(destination, force_windows_long=(os.name == "nt"))
    if _path_exists(target):
        if target.is_symlink():
            raise RuntimeError("existing extracted bundle differs")
        try:
            verification = verify_extracted_bundle(target)
            current_manifest = _read_json(target / INTERNAL_MANIFEST_NAME)
        except Exception as error:
            raise RuntimeError("existing extracted bundle differs") from error
        if current_manifest != internal:
            raise RuntimeError("existing extracted bundle differs")
        return {**verification, "reused": True, "destination": str(target)}

    target.parent.mkdir(parents=True, exist_ok=True)
    pending = target.with_name(target.name + f".pending-{uuid.uuid4().hex[:8]}")
    if _path_exists(pending):
        raise RuntimeError(f"pending extraction path already exists: {pending}")
    pending.mkdir(parents=False, exist_ok=False)
    pending_resolved = pending.resolve(strict=True)
    try:
        for name in sorted(payloads):
            destination_path = pending.joinpath(*PurePosixPath(name).parts)
            resolved = destination_path.resolve(strict=False)
            if pending_resolved not in resolved.parents:
                raise RuntimeError(f"archive member escapes pending root: {name}")
            destination_path.parent.mkdir(parents=True, exist_ok=True)
            with destination_path.open("xb") as handle:
                handle.write(payloads[name])
                handle.flush()
                os.fsync(handle.fileno())
            if name.endswith((".slurm", ".sh")):
                destination_path.chmod(0o755)
        verification = verify_extracted_bundle(pending)
        if _path_exists(target):
            raise RuntimeError("extraction destination appeared before publication")
        os.replace(pending, target)
    finally:
        if _path_exists(pending):
            shutil.rmtree(pending)
    return {**verification, "reused": False, "destination": str(target)}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build, verify, or safely extract the deterministic TUKF09 455-basin HPC bundle."
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_BUNDLE_OUTPUT)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--extract-to", type=Path)
    parser.add_argument("--verify-extracted", type=Path)
    parser.add_argument("--verify-runtime", type=Path)
    args = parser.parse_args()

    if args.verify_extracted is not None and args.verify_runtime is not None:
        parser.error("--verify-extracted and --verify-runtime are mutually exclusive")
    if args.verify_extracted is not None:
        if args.archive is not None or args.extract_to is not None:
            parser.error("--verify-extracted cannot be combined with archive extraction")
        payload = verify_extracted_bundle(args.verify_extracted)
    elif args.verify_runtime is not None:
        if args.archive is not None or args.extract_to is not None:
            parser.error("--verify-runtime cannot be combined with archive extraction")
        payload = verify_runtime_bundle(args.verify_runtime)
    elif args.archive is not None:
        if args.extract_to is None:
            parser.error("--archive requires --extract-to")
        payload = extract_bundle(args.archive, args.extract_to)
    else:
        bundle = build_bundle(args.output)
        payload = {
            "archive": str(bundle.archive_path),
            "archive_sha256": bundle.archive_sha256,
            "archive_size": bundle.archive_size,
            "manifest": str(bundle.manifest_path),
            "member_count": len(bundle.member_sha256),
            "admitted_executable_count": EXPECTED_ADMITTED_EXECUTABLE_COUNT,
            "admitted_test_count": EXPECTED_ADMITTED_TEST_COUNT,
            "submitted": False,
        }
        if args.extract_to is not None:
            payload["extraction"] = extract_bundle(bundle.archive_path, args.extract_to)
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
