#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
SOURCE="$TARGET/source"
OUTPUT="$TARGET/results/tukf06_full_diagonal_search_head_to_head_v1"

echo "=== FORMAL SELECTION GUARDS ==="
test -d "$SOURCE"
test -f "$SOURCE/bundle_manifest.json"
if [[ -e "$OUTPUT" ]]; then
  echo "formal selection output already exists; refusing overwrite: $OUTPUT" >&2
  exit 61
fi
if squeue -u "$USER" -h -n tukf06-select -o '%i' | grep -q .; then
  echo "an existing tukf06-select job is queued or running" >&2
  exit 62
fi
python - "$SOURCE" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
manifest = json.loads((root / 'bundle_manifest.json').read_text(encoding='utf-8'))
for relative, expected in manifest['member_sha256'].items():
    path = root / relative
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit(f'formal selection source mismatch: {relative}')
print(f"verified_members={len(manifest['member_sha256'])}")
PY

echo "=== SUBMIT FORMAL TRAINING-VALIDATION SELECTION ==="
JID=$(sbatch --parsable "$SOURCE/hpc/tukf06_full_diagonal/submit_selection_cpu.slurm")
echo "jobid=$JID"
printf '%s\n' "$JID" > "$TARGET/results/selection_job_id.txt"
squeue -j "$JID" -o '%.18i %.24j %.10P %.8T %.10M %.20R'
scontrol show job "$JID"
