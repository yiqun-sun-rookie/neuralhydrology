#!/bin/bash
# Read-only search for exact copies of the three frozen training/validation
# forcing files that differ in the current shared CAMELS-US source tree.
# No scheduler submission, process control, write, or formal-evaluation access.
set -eo pipefail
umask 077

PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
SEARCH_ROOT=/data1/home/sunyiq
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1

[[ -x "${PYTHON}" ]] || { echo "FATAL: bootstrap Python is unavailable" >&2; exit 1; }
[[ -d "${SEARCH_ROOT}" && ! -L "${SEARCH_ROOT}" ]] || { echo "FATAL: search root is unavailable or linked" >&2; exit 1; }

"${PYTHON}" -B - "${SEARCH_ROOT}" <<'PY'
from __future__ import annotations

from hashlib import sha256
import json
import os
from pathlib import Path
import stat
import sys

search_root = Path(sys.argv[1])
expected = {
    "basin_mean_forcing/maurer/03/02108000_lump_maurer_forcing_leap.txt": {
        "size": 627964,
        "sha256": "1d7efcfdcf87cda0485a7f6442f7d85aaacaf0b33e0e1c01dddeb73896f26a1a",
    },
    "basin_mean_forcing/maurer/09/05120500_lump_maurer_forcing_leap.txt": {
        "size": 625295,
        "sha256": "60d14109d2e24cd0a461798fce6a9214aa0b022b349e13de2fafcbbbf995431b",
    },
    "basin_mean_forcing/maurer/15/09492400_lump_maurer_forcing_leap.txt": {
        "size": 617721,
        "sha256": "d51780287addd95ad0f874da42fc3a2e2fa47e43437f3b0c85b2375f238116af",
    },
}

def digest(path: Path) -> str:
    value = sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

# Locate candidate CAMELS roots by directory topology. os.walk does not follow
# symbolic links. Large dependency, Git, and runtime trees cannot contain a
# legitimate basin_mean_forcing/maurer source route and are pruned.
prune_exact = {
    ".git", ".cache", "__pycache__", "miniconda3", "node_modules",
    "offline_inputs_v2", "offline_inputs_v2r1", "offline_inputs_v2r2", "offline_inputs_v2r3",
    "runtime_v2", "runtime_v2r1", "runtime_v2r2", "runtime_v2r3",
}
prune_prefixes = ("pysite", "wheelhouse")
candidate_roots: set[Path] = set()
visited_directory_count = 0
for directory, names, _files in os.walk(search_root, topdown=True, followlinks=False):
    visited_directory_count += 1
    kept: list[str] = []
    for name in names:
        candidate = Path(directory) / name
        try:
            info = os.lstat(candidate)
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode):
            continue
        if name in prune_exact or name.startswith(prune_prefixes):
            continue
        kept.append(name)
    names[:] = kept
    here = Path(directory)
    if here.name == "basin_mean_forcing" and (here / "maurer").is_dir():
        candidate_roots.add(here.parent)
        names[:] = []

rows: list[dict[str, object]] = []
exact_path_count_by_relative = {relative: 0 for relative in expected}
complete_exact_roots: list[str] = []
for root in sorted(candidate_roots, key=lambda value: str(value)):
    root_rows: list[dict[str, object]] = []
    root_exact = True
    for relative, wanted in sorted(expected.items()):
        path = root.joinpath(*relative.split("/"))
        row: dict[str, object] = {"root": str(root), "relative_path": relative, "path": str(path)}
        try:
            info = os.lstat(path)
        except FileNotFoundError:
            row["state"] = "missing"
            root_exact = False
            root_rows.append(row)
            continue
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            row.update({"state": "irregular", "size": info.st_size, "link_count": info.st_nlink})
            root_exact = False
            root_rows.append(row)
            continue
        actual_sha = digest(path)
        matches = info.st_size == int(wanted["size"]) and actual_sha == str(wanted["sha256"])
        row.update({
            "state": "exact" if matches else "different",
            "size": info.st_size,
            "sha256": actual_sha,
            "link_count": info.st_nlink,
        })
        if matches:
            exact_path_count_by_relative[relative] += 1
        else:
            root_exact = False
        root_rows.append(row)
    rows.extend(root_rows)
    if root_exact:
        complete_exact_roots.append(str(root))

summary = {
    "candidate_root_count": len(candidate_roots),
    "complete_exact_root_count_for_all_three_files": len(complete_exact_roots),
    "complete_exact_roots": complete_exact_roots,
    "exact_path_count_by_relative": exact_path_count_by_relative,
    "formal_evaluation_array_reads": 0,
    "searched_relative_path_count": len(expected),
    "visited_directory_count": visited_directory_count,
}
print("SUMMARY=" + json.dumps(summary, ensure_ascii=False, sort_keys=True))
print("CANDIDATE_RECORDS_BEGIN")
for row in rows:
    print(json.dumps(row, ensure_ascii=False, sort_keys=True))
print("CANDIDATE_RECORDS_END")

if not all(exact_path_count_by_relative.values()):
    print("TUKF09_455_V2R4_EXACT_SOURCE_ROUTE_NOT_YET_PROVEN")
else:
    print("TUKF09_455_V2R4_EXACT_SOURCE_FILE_CANDIDATES_PROVEN")
PY
