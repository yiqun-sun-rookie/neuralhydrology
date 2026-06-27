"""Level-1 forbidden-data-access scan (the cheap data-tap teeth).

Threat model: your own optimizing agent taking the lazy path and reading the
answer (observed discharge, or signatures derived from it) while producing
predictions — NOT a hostile attacker defeating isolation. So we do NOT need an
OS sandbox; we need (a) the challenger to read only allowed inputs and (b) a
heuristic that surfaces forbidden reads to the independent auditor.

This is a static heuristic, defeatable by renaming/obfuscation — that is fine.
Its job is to make an accidental/lazy obs read VISIBLE (a hit forces HOLD for
audit, never a silent PASS), not to be cryptographically airtight. Track-aware:
Track 1 (past observed Q allowed) passes a reduced pattern list.
"""
import re
from pathlib import Path

# Track-0 forbidden tokens: observed discharge files/columns + hydro signatures
# that are computed FROM observed discharge over a window overlapping eval.
DEFAULT_FORBIDDEN = [
    r"usgs_streamflow",          # CAMELS observed discharge files
    r"streamflow_qc",
    r"camels_hydro",             # hydro-signature attribute table
    r"QObs",                     # observed discharge column
    r"_obs_eval\.parquet",       # the held answer key itself
    r"runoff_ratio", r"baseflow_index", r"\bq_mean\b",
    r"\bq5\b", r"\bq95\b", r"high_q_freq", r"low_q_freq",
    r"zero_q_freq", r"hfd_mean", r"slope_fdc",
]

SCAN_EXTS = {".py", ".ipynb", ".sh", ".bash", ".yml", ".yaml", ".json", ".cfg", ".toml", ".r", ".jl"}


def scan_for_forbidden_access(experiment_dir, patterns=None) -> list:
    """Return a list of {file, line, pattern, text} hits for forbidden tokens."""
    patterns = list(DEFAULT_FORBIDDEN if patterns is None else patterns)
    compiled = [(p, re.compile(p)) for p in patterns]
    hits = []
    for path in sorted(Path(experiment_dir).rglob("*")):
        if not path.is_file() or path.suffix.lower() not in SCAN_EXTS:
            continue
        try:
            lines = path.read_text(errors="ignore").splitlines()
        except OSError:
            continue
        for lineno, line in enumerate(lines, 1):
            for pat, rx in compiled:
                if rx.search(line):
                    hits.append({"file": str(path), "line": lineno,
                                 "pattern": pat, "text": line.strip()[:200]})
    return hits


def leakage_ok(experiment_dir, patterns=None) -> bool:
    return len(scan_for_forbidden_access(experiment_dir, patterns)) == 0
