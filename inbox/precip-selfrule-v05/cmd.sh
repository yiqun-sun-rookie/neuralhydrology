#!/bin/bash
# precip-selfrule-v05 seq=26: locate the frozen ID29 files from the pinned reference manifest.
set -eo pipefail

ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_concurrency4_probe_20260929
REF=/data1/home/sunyiq/precip_input_selfrule_time_v05_batch384_probe_20260929/reference_batch128/run01/RUN_MANIFEST.json

date "+wallclock %F %T %z"
test ! -e "$ROOT" || { echo "PROBE_ROOT_ALREADY_EXISTS=$ROOT"; exit 1; }
python - "$REF" <<'PY'
import hashlib, json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
wanted = {"assimilation.py", "assimilationconfig.py"}
found = []
for entry in manifest["source_files"]:
    path = pathlib.Path(entry["path"])
    if path.name in wanted:
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        found.append((path.name, str(path), entry["sha256"], actual))
if {row[0] for row in found} != wanted:
    raise SystemExit(f"FROZEN_FILES_NOT_UNIQUELY_FOUND {found}")
for name, path, recorded, actual in sorted(found):
    print(f"{name}|{path}|{recorded}|{actual}")
PY
