"""Compatibility module forwarding to `src/hydroagent/environment.py`."""

from pathlib import Path
import sys

_SRC_ROOT = Path(__file__).resolve().parents[2] / "src"
if str(_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(_SRC_ROOT))

from hydroagent.environment import *  # noqa: F401,F403
