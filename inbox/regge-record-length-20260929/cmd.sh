#!/bin/bash
set -eo pipefail
sequence=9

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
STAGE="$ROOT/runtime_stage_003"
PREFIX="$ROOT/runtime_probe_003"
MICROMAMBA="$ROOT/runtime_stage_002/tool/bin/micromamba"

test -d "$ROOT"
echo "=== read-only diagnosis of failed complete runtime build ==="
printf 'root=%s\nstage=%s\nprefix=%s\n' "$ROOT" "$STAGE" "$PREFIX"
for target in "$STAGE" "$PREFIX" "$MICROMAMBA"; do
  if [ -e "$target" ]; then
    printf 'exists=yes path=%s\n' "$target"
  else
    printf 'exists=no path=%s\n' "$target"
  fi
done

echo "=== failure receipt and stage files ==="
if [ -f "$STAGE/runtime_failed.txt" ]; then
  sed -n '1,80p' "$STAGE/runtime_failed.txt"
fi
if [ -d "$STAGE" ]; then
  find "$STAGE" -maxdepth 2 -type f -printf '%p %s bytes\n' | sort
fi

echo "=== partial prefix metadata ==="
if [ -d "$PREFIX" ]; then
  du -sh "$PREFIX"
  if [ -f "$PREFIX/conda-meta/history" ]; then
    tail -80 "$PREFIX/conda-meta/history"
  fi
  if [ -x "$PREFIX/bin/python" ]; then
    "$PREFIX/bin/python" - <<'PY'
import importlib
import platform
mods = ("numpy", "pandas", "torch", "psutil", "matplotlib", "pytest", "threadpoolctl")
print("python", platform.python_version())
for name in mods:
    try:
        module = importlib.import_module(name)
        print(name, getattr(module, "__version__", "NO_VERSION"))
    except Exception as exc:
        print(name, "IMPORT_FAILED", type(exc).__name__, str(exc))
PY
  fi
fi

echo "=== package cache and capacity ==="
df -h "$ROOT"
du -sh "$ROOT/runtime_stage_002/mamba_root/pkgs" 2>/dev/null || true
find "$ROOT/runtime_stage_002/mamba_root/pkgs" -maxdepth 1 -type d \
  \( -name 'pandas-*' -o -name 'matplotlib-base-*' -o -name 'pytest-*' -o -name 'conda-pack-*' \) \
  -printf '%f\n' | sort | tail -80
