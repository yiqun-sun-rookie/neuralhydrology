import sys
import importlib.metadata
from pathlib import Path

import pytest


SRC = Path(__file__).resolve().parents[2]
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))


@pytest.fixture(scope="session")
def frozen_dependencies_for_active_environment() -> tuple[str, ...]:
    """Return an exact predeclared dependency set, never an arbitrary environment-derived set."""
    from unified_autoresearch.candidates.catalog import FROZEN_DEPENDENCY_SETS

    installed = tuple(
        f"{name}=={importlib.metadata.version(name)}" for name in ("numpy", "pandas", "pyarrow")
    )
    if installed not in FROZEN_DEPENDENCY_SETS:
        pytest.fail(f"active test environment does not match a frozen dependency set: {installed!r}")
    return installed
