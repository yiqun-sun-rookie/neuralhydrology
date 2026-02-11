"""Compatibility layer for HydroAgent's new package path (`src/hydroagent`)."""

from pathlib import Path
import sys

_SRC_ROOT = Path(__file__).resolve().parents[2] / "src"
if str(_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(_SRC_ROOT))

from hydroagent import HydroAgent, HydroDiagnostician, SuperflexEnv

__all__ = ["HydroAgent", "HydroDiagnostician", "SuperflexEnv"]
