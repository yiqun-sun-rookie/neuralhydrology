"""Put repo_root/src on sys.path so `import fair_benchmark` works.

src/ idea workspaces are not installed by `pip install -e .` (only the
neuralhydrology package is), so tests must bootstrap the path. Run with:
    pytest src/fair_benchmark/tests -v
"""
import sys
from pathlib import Path

_SRC = Path(__file__).resolve().parents[2]  # .../src
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))
