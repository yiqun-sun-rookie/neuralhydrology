#!/usr/bin/env bash
# zhenjiang out-of-year validation :: qualification step 3
# READ-ONLY. Emit the full qualification report so the preregistration can pin
# the measured cluster environment by value. No sbatch, no writes, no installs.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_qual_20260819

echo "=== A. REPORT FILE IDENTITIES ==="
for f in "$ROOT"/reports/qual_205525_0.json "$ROOT"/reports/qual_205525_1.json; do
    if [ -f "$f" ]; then
        printf '%s  %s  %s bytes\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")" "$(stat -c %s "$f")"
    else
        echo "MISSING $f"
    fi
done

echo "=== B. FULL RUNTIME IDENTITY (task 0, node ngu011) ==="
sed -n '/"runtime_identity"/,/^  },$/p' "$ROOT/reports/qual_205525_0.json" || true

echo "=== C. FULL RUNTIME IDENTITY (task 1, node ngu008) ==="
sed -n '/"runtime_identity"/,/^  },$/p' "$ROOT/reports/qual_205525_1.json" || true

echo "=== D. NUMPY DIRECTION CHECK (task 0) ==="
sed -n '/"numpy_direction_check"/,/"observed"/p' "$ROOT/reports/qual_205525_0.json" | head -30 || true

echo "=== E. INSTALLED PRIVATE PACKAGE VERSIONS ==="
ls -1 "$ROOT/pysite" | grep -E 'dist-info$' || true

echo "=== F. PARTITION SNAPSHOT ==="
sinfo -p hgpu2p -o '%.10P %.6a %.6D %.28N %.10T' 2>&1 | head -10 || true
squeue -u "$USER" -h -o '%.10i %.10P %.9T' 2>&1 | wc -l || true

echo "=== END ==="
