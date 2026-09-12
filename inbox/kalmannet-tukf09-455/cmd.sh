#!/bin/bash
# TUKF09-455: read-only. Size the finished result tree and confirm the provenance path style.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909
R="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
echo "TIME=$(date -Is)"
echo "=== SIZE OF EACH TOP-LEVEL MEMBER ==="
du -sb "$R"/* 2>/dev/null | sort -n
echo "TOTAL_BYTES=$(du -sb "$R" | cut -f1)"
echo "FILE_COUNT=$(find "$R" -type f | wc -l)"
echo "SYMLINKS=$(find "$R" -type l | wc -l)"
echo "HARDLINKED=$(find "$R" -type f -links +1 | wc -l)"

echo "=== CONTROL AND LOGS ==="
find "$R/control" "$R/logs" -maxdepth 2 2>/dev/null | head -40
echo "PHASE_LOCK=$(test -e "$R/control/.training_phase.lock" && echo present || echo absent)"

echo "=== ONE NEURAL UNIT, ONE FILTER UNIT ==="
ls -la "$R/neural/lead_1_seed_0" "$R/neural/shared" | head -30
ls -la "$R/neural/lead_1_seed_0/checkpoints" | head -5
ls -la "$R/filter/basin_01022500"

echo "=== THE PROVENANCE PATH AS STORED ON THE CLUSTER ==="
python -X utf8 -c "import json,pathlib;p=json.load(open('$R/filter/basin_01022500/migration_provenance.json'));s=p['source_unit_path'];print(repr(s));print('posix_is_absolute=',pathlib.PurePosixPath(s).is_absolute())"

echo "=== CHECKSUMS OF THE FIVE ROOT SNAPSHOTS ==="
(cd "$R" && sha256sum authorization.snapshot.json scientific_contract.snapshot.json execution_config.snapshot.json training_admission.snapshot.json training_context.json)

echo TUKF09_455_V2R14_SIZE_READ_ONLY_DONE
