"""Bind exact candidate dependency declarations to the launch environment."""

from __future__ import annotations

import importlib.metadata
import json
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass


def _canonical_name(value: str) -> str:
    return re.sub(r"[-_.]+", "-", value).lower()


@dataclass(frozen=True)
class DependencyMatch:
    declaration: str
    package_name: str
    requested_version: str
    installed_versions: tuple[str, ...]
    active_version: str | None
    active_module_path: str | None
    active_probe_error: str | None
    matched: bool


@dataclass(frozen=True)
class DependencyAssessment:
    requested: tuple[str, ...]
    matches: tuple[DependencyMatch, ...]
    initialization_read_roots: tuple[str, ...]
    initialization_probe_error: str | None
    decision: str

    def as_dict(self) -> dict:
        return {
            "schema_version": "dependency_preflight_v1",
            "requested": list(self.requested),
            "matches": [asdict(match) for match in self.matches],
            "initialization_read_roots": list(self.initialization_read_roots),
            "initialization_probe_error": self.initialization_probe_error,
            "decision": self.decision,
        }


class DependencyEnvironmentError(RuntimeError):
    """Raised before candidate launch when exact dependencies are unavailable."""

    def __init__(self, assessment: DependencyAssessment):
        super().__init__("declared dependency environment does not match")
        self.assessment = assessment


def _probe_active_module(package_name: str) -> tuple[str | None, str | None, str | None]:
    """Ask a clean child interpreter which module the runtime will actually import."""
    module_name = package_name.replace("-", "_")
    source = (
        "import importlib,json,sys; "
        "module=importlib.import_module(sys.argv[1]); "
        "print(json.dumps({'version':getattr(module,'__version__',None),"
        "'path':getattr(module,'__file__',None)}))"
    )
    try:
        completed = subprocess.run(
            [sys.executable, "-I", "-B", "-c", source, module_name],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, None, f"{type(error).__name__}: {error}"
    if completed.returncode != 0:
        detail = completed.stderr.strip() or f"child exit code {completed.returncode}"
        return None, None, detail[:2048]
    try:
        value = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        return None, None, f"invalid active module probe output: {error}"
    version = value.get("version")
    path = value.get("path")
    if not isinstance(version, str) or not version or not isinstance(path, str) or not path:
        return None, None, "active module does not expose a version and file path"
    return version, path, None


def _probe_dependency_initialization_roots(package_names: tuple[str, ...]) -> tuple[tuple[str, ...], str | None]:
    """Record the site-package paths loaded while the declared dependencies initialize."""
    if not package_names:
        return (), None
    module_names = tuple(package_name.replace("-", "_") for package_name in package_names)
    source = "\n".join(
        (
            "import importlib,json,os,sys,sysconfig",
            "site_roots=sorted({os.path.realpath(value) for key,value in sysconfig.get_paths().items() "
            "if key in {'purelib','platlib'} and value})",
            "before=set(sys.modules)",
            "loaded=[importlib.import_module(name) for name in sys.argv[1:]]",
            "roots=set()",
            "for name in sorted(set(sys.modules)-before):",
            " module=sys.modules.get(name)",
            " path=getattr(module,'__file__',None)",
            " if not isinstance(path,str): continue",
            " path=os.path.realpath(path)",
            " for site_root in site_roots:",
            "  try: within=os.path.commonpath((path,site_root))==site_root",
            "  except ValueError: within=False",
            "  if not within: continue",
            "  relative=os.path.relpath(path,site_root)",
            "  top_level=relative.split(os.sep,1)[0]",
            "  top_path=os.path.join(site_root,top_level)",
            "  if os.path.isdir(top_path): roots.add(os.path.realpath(top_path))",
            "  else:",
            "   roots.add(path)",
            "   cached=getattr(module,'__cached__',None)",
            "   if isinstance(cached,str): roots.add(os.path.realpath(cached))",
            "print(json.dumps({'roots':sorted(roots)}))",
        )
    )
    try:
        completed = subprocess.run(
            [sys.executable, "-I", "-B", "-c", source, *module_names],
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return (), f"{type(error).__name__}: {error}"
    if completed.returncode != 0:
        detail = completed.stderr.strip() or f"child exit code {completed.returncode}"
        return (), detail[:2048]
    try:
        value = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        return (), f"invalid dependency initialization probe output: {error}"
    roots = value.get("roots")
    if not isinstance(roots, list) or any(not isinstance(path, str) or not path for path in roots):
        return (), "dependency initialization probe did not return path roots"
    return tuple(roots), None


def assess_dependency_environment(declarations: tuple[str, ...]) -> DependencyAssessment:
    """Bind declarations to the module version selected by a clean active interpreter."""
    inventory: dict[str, set[str]] = defaultdict(set)
    for distribution in importlib.metadata.distributions():
        name = distribution.metadata.get("Name")
        if name:
            inventory[_canonical_name(name)].add(str(distribution.version))

    matches = []
    for declaration in declarations:
        package_name, requested_version = declaration.split("==", 1)
        installed_versions = tuple(sorted(inventory.get(_canonical_name(package_name), set())))
        active_version, active_module_path, active_probe_error = _probe_active_module(package_name)
        if active_version is not None:
            matched = active_version == requested_version and requested_version in installed_versions
        else:
            matched = installed_versions == (requested_version,)
        matches.append(
            DependencyMatch(
                declaration=declaration,
                package_name=package_name,
                requested_version=requested_version,
                installed_versions=installed_versions,
                active_version=active_version,
                active_module_path=active_module_path,
                active_probe_error=active_probe_error,
                matched=matched,
            )
        )
    initialization_read_roots, initialization_probe_error = _probe_dependency_initialization_roots(
        tuple(declaration.split("==", 1)[0] for declaration in declarations)
    )
    return DependencyAssessment(
        requested=declarations,
        matches=tuple(matches),
        initialization_read_roots=initialization_read_roots,
        initialization_probe_error=initialization_probe_error,
        decision=(
            "launch"
            if all(match.matched for match in matches) and initialization_probe_error is None
            else "deny"
        ),
    )
