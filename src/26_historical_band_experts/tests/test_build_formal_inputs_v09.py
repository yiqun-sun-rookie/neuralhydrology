import inspect
import os
from pathlib import Path
import subprocess
import sys

import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
WORKTREE_ROOT = IDEA_ROOT.parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _formal_files():
    root = WORKTREE_ROOT / "results/26_historical_band_experts/formal_v09"
    return sorted(path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file())


def test_help_and_import_are_read_only(tmp_path):
    before = _formal_files()
    temporary_root = tmp_path / "import-temp"
    temporary_root.mkdir()
    environment = os.environ.copy()
    environment.update({
        "TEMP": str(temporary_root),
        "TMP": str(temporary_root),
        "PYTHONDONTWRITEBYTECODE": "1",
    })
    completed = subprocess.run(
        [sys.executable, str(IDEA_ROOT / "build_formal_inputs_v09.py"), "--help"],
        cwd=WORKTREE_ROOT,
        capture_output=True,
        text=True,
        env=environment,
    )
    assert completed.returncode == 0
    assert _formal_files() == before
    assert list(temporary_root.iterdir()) == []


def test_public_formal_entry_has_no_path_or_resource_injection_and_fails_without_authorization():
    from build_formal_inputs_v09 import build_formal_input_seal_v09

    assert list(inspect.signature(build_formal_input_seal_v09).parameters) == []
    before = _formal_files()
    with pytest.raises(FileNotFoundError, match="authorization"):
        build_formal_input_seal_v09()
    assert _formal_files() == before


def test_public_formal_entry_checks_reparse_components_before_authorization(monkeypatch):
    import build_formal_inputs_v09 as module

    monkeypatch.setattr(
        module,
        "assert_no_reparse_components",
        lambda root, target: (_ for _ in ()).throw(ValueError("synthetic reparse")),
    )
    with pytest.raises(ValueError, match="synthetic reparse"):
        module.build_formal_input_seal_v09()


def test_public_formal_entry_checks_each_exact_sensitive_path(monkeypatch):
    import build_formal_inputs_v09 as module

    checked = []
    monkeypatch.setattr(
        module,
        "assert_no_reparse_components",
        lambda root, target: checked.append(Path(target)),
    )
    with pytest.raises(FileNotFoundError, match="authorization"):
        module.build_formal_input_seal_v09()
    assert module.WORKTREE_ROOT / module.AUTHORIZATION_RELATIVE in checked
    assert module.WORKTREE_ROOT / module.CONSUMPTION_RELATIVE in checked
    assert module.WORKTREE_ROOT / module.FORMAL_BUILDING_RELATIVE in checked
    assert module.WORKTREE_ROOT / module.FORMAL_OUTPUT_RELATIVE in checked


def test_source_boundary_scanner_rejects_protocol_forbidden_interface(tmp_path):
    from audit_formal_inputs_v09 import audit_input_source_boundary_v09

    path = tmp_path / "candidate.py"
    path.write_text("source = 'BLOCKED' + '_INPUT'\n", encoding="utf-8")
    protocol = {"forbidden_inputs": ["blocked_input"]}
    with pytest.raises(ValueError, match="forbidden"):
        audit_input_source_boundary_v09(
            tmp_path,
            relative_paths=("candidate.py",),
            protocol=protocol,
        )
