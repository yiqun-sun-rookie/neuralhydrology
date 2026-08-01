"""Install runtime restrictions before executing one candidate entrypoint."""

from __future__ import annotations

import argparse
import importlib
import json
import os
import runpy
import sys
from importlib.machinery import PathFinder
from pathlib import Path
from typing import Any, Callable


FORBIDDEN_IMPORTS = {
    "_overlapped",
    "_winapi",
    "msvcrt",
    "multiprocessing",
    "subprocess",
    "winreg",
}


def _install_file_hook(policy: dict[str, Any], log_descriptor: int) -> Callable[[bool], None]:
    abspath = os.path.abspath
    commonpath = os.path.commonpath
    fsdecode = os.fsdecode
    fsync = os.fsync
    getcwd = os.getcwd
    isfile = os.path.isfile
    join = os.path.join
    json_encode = json.JSONEncoder(
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode
    normcase = os.path.normcase
    realpath = os.path.realpath
    terminate_process = os._exit
    raw_write = os.write
    write_flags = os.O_WRONLY | os.O_RDWR | os.O_APPEND | os.O_CREAT | os.O_TRUNC
    forbidden_imports = frozenset(FORBIDDEN_IMPORTS)
    stdlib_module_names = frozenset(sys.stdlib_module_names)
    module_search_path = tuple(sys.path)

    def normalize(path: str) -> str:
        return normcase(realpath(abspath(path)))

    def inside(path: str, roots: tuple[str, ...]) -> bool:
        normalized = normalize(path)
        for root in roots:
            try:
                if commonpath((normalized, root)) == root:
                    return True
            except ValueError:
                continue
        return False

    def classify_operation(mode: Any, flags: Any) -> str:
        if isinstance(mode, str) and any(character in mode for character in "wax+"):
            return "write"
        if isinstance(flags, int) and flags & write_flags:
            return "write"
        return "read"

    def write_event(event: dict[str, Any]) -> None:
        payload = json_encode(event).encode("utf-8") + b"\n"
        raw_write(log_descriptor, payload)
        fsync(log_descriptor)

    def reject(event: dict[str, Any]) -> None:
        try:
            write_event(event)
        finally:
            terminate_process(2)

    read_roots = tuple(normalize(path) for path in policy["read_roots"])
    write_roots = tuple(normalize(path) for path in policy["write_roots"])
    restricted_site_package_roots = tuple(
        normalize(path) for path in policy.get("restricted_site_package_roots", ())
    )
    dependency_initialization_read_roots = tuple(
        normalize(path) for path in policy.get("dependency_initialization_read_roots", ())
    )
    candidate_root = normalize(policy["candidate_root"])
    allowed_dependencies = set(policy["allowed_dependency_imports"])
    dependency_initialization = True
    allowed_initialization_libraries = frozenset({"kernel32", "user32", "tzres.dll"})
    allowed_initialization_symbols = frozenset({"GetLastError", "LoadStringW"})

    def deny(event: str, reason: str, **details: Any) -> None:
        reject({"event": event, "decision": "deny", "reason": reason, **details})

    def path_allowed(path: str, roots: tuple[str, ...], operation: str) -> bool:
        allowed = inside(path, roots)
        if (
            allowed
            and operation == "read"
            and inside(path, restricted_site_package_roots)
            and not inside(path, dependency_initialization_read_roots)
        ):
            return False
        return allowed

    def audit_path(event: str, path: Any, operation: str) -> None:
        if path is None:
            decoded = getcwd()
        elif isinstance(path, (str, bytes, os.PathLike)):
            decoded = fsdecode(path)
        else:
            deny(event, "candidate path operation has an unsupported path")
            return
        roots = write_roots if operation == "write" else read_roots
        allowed = path_allowed(decoded, roots, operation)
        record = {
            "event": event,
            "operation": operation,
            "path": abspath(decoded),
            "decision": "allow" if allowed else "deny",
        }
        if allowed:
            write_event(record)
        else:
            reject(record)

    def audit(event: str, arguments: tuple[Any, ...]) -> None:
        if event == "import":
            module = str(arguments[0]) if arguments else ""
            top_level = module.partition(".")[0]
            if top_level in forbidden_imports and not dependency_initialization:
                reject(
                    {
                        "event": event,
                        "module": module,
                        "decision": "deny",
                        "reason": "raw operating-system capability is disabled",
                    },
                )
            local_module = isfile(join(candidate_root, *top_level.split("."))) or isfile(
                join(candidate_root, *top_level.split(".")) + ".py"
            )
            missing_module = (
                not local_module
                and top_level not in stdlib_module_names
                and PathFinder.find_spec(top_level, module_search_path) is None
            )
            allowed = (
                dependency_initialization
                or top_level in stdlib_module_names
                or top_level in allowed_dependencies
                or local_module
                or missing_module
            )
            record = {
                "event": event,
                "module": module,
                "decision": "allow" if allowed else "deny",
                "reason": (
                    "declared dependency initialization"
                    if dependency_initialization
                    else "missing optional import will resolve to ImportError"
                    if missing_module
                    else "declared or standard dependency"
                    if allowed
                    else "undeclared dependency"
                ),
            }
            if allowed:
                write_event(record)
            else:
                reject(record)
            return
        if event.startswith("subprocess.") or event in {
            "os.system",
            "os.posix_spawn",
            "os.spawn",
            "os.startfile",
            "os.startfile/2",
        }:
            deny(event, "candidate child processes are disabled")
        if event.startswith("socket."):
            deny(event, "candidate network access is disabled")
        if event.startswith("ctypes."):
            library = arguments[0] if arguments else None
            symbol = arguments[1] if len(arguments) > 1 else None
            allowed_initialization_event = dependency_initialization and (
                (event == "ctypes.dlopen" and library in allowed_initialization_libraries)
                or (event == "ctypes.dlsym" and symbol in allowed_initialization_symbols)
            )
            if allowed_initialization_event:
                write_event(
                    {
                        "event": event,
                        "decision": "allow",
                        "reason": "declared dependency initialization requires a fixed Windows system library",
                        "library": str(library),
                        "symbol": None if symbol is None else str(symbol),
                    }
                )
                return
            deny(event, "candidate dynamic local library loading is disabled")
        if event in {"os.listdir", "os.scandir"}:
            audit_path(event, arguments[0] if arguments else None, "read")
            return
        if event == "os.mkdir":
            audit_path(event, arguments[0] if arguments else None, "write")
            return
        if event in {"os.remove", "os.rmdir", "os.chmod", "os.utime", "os.truncate"}:
            audit_path(event, arguments[0] if arguments else None, "write")
            return
        if event == "os.rename":
            audit_path(event, arguments[0] if arguments else None, "write")
            audit_path(event, arguments[1] if len(arguments) > 1 else None, "write")
            return
        if event == "os.link":
            audit_path(event, arguments[0] if arguments else None, "read")
            audit_path(event, arguments[1] if len(arguments) > 1 else None, "write")
            return
        if event != "open":
            return
        path = arguments[0] if arguments else None
        mode = arguments[1] if len(arguments) > 1 else None
        flags = arguments[2] if len(arguments) > 2 else None
        if isinstance(path, int):
            return
        if not isinstance(path, (str, bytes, os.PathLike)):
            write_event({"event": event, "decision": "deny", "reason": "unsupported path"})
            raise PermissionError("candidate file access has an unsupported path")
        decoded = fsdecode(path)
        requested_operation = classify_operation(mode, flags)
        roots = write_roots if requested_operation == "write" else read_roots
        allowed = path_allowed(decoded, roots, requested_operation)
        record = {
            "event": event,
            "operation": requested_operation,
            "path": abspath(decoded),
            "decision": "allow" if allowed else "deny",
        }
        if allowed:
            write_event(record)
        else:
            reject(record)

    sys.addaudithook(audit)
    write_event(
        {
            "event": "bootstrap.dependency_initialization",
            "phase": "start",
            "decision": "allow",
        }
    )

    def finish_dependency_initialization(succeeded: bool) -> None:
        nonlocal dependency_initialization
        dependency_initialization = False
        write_event(
            {
                "event": "bootstrap.dependency_initialization",
                "phase": "complete",
                "decision": "allow" if succeeded else "deny",
            }
        )

    return finish_dependency_initialization


def _parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", required=True)
    parser.add_argument("--access-log", required=True)
    parser.add_argument("--entrypoint", required=True)
    parser.add_argument("--mode", choices=("train", "predict"), required=True)
    return parser.parse_args()


def main() -> int:
    arguments = _parse_arguments()
    policy = json.loads(Path(arguments.policy).read_text(encoding="utf-8"))
    log_descriptor = os.open(arguments.access_log, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    try:
        finish_dependency_initialization = _install_file_hook(policy, log_descriptor)
        dependency_initialization_succeeded = False
        try:
            for module_name in policy["allowed_dependency_imports"]:
                importlib.import_module(module_name)
            dependency_initialization_succeeded = True
        finally:
            finish_dependency_initialization(dependency_initialization_succeeded)
        for module_name in FORBIDDEN_IMPORTS:
            sys.modules.pop(module_name, None)
        sys.dont_write_bytecode = True
        sys.path.insert(0, policy["candidate_root"])
        sys.argv = [arguments.entrypoint, arguments.mode]
        try:
            runpy.run_path(arguments.entrypoint, run_name="__main__")
        except PermissionError as error:
            print(f"contract failure: {error}", file=sys.stderr)
            return 2
        except SystemExit as error:
            if error.code is None:
                return 0
            if isinstance(error.code, int):
                return error.code
            print(f"runtime failure: {error.code}", file=sys.stderr)
            return 1
        except BaseException as error:
            print(f"runtime failure: {type(error).__name__}: {error}", file=sys.stderr)
            return 1
        return 0
    finally:
        os.close(log_descriptor)


if __name__ == "__main__":
    raise SystemExit(main())
