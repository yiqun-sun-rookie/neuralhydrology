#!/bin/bash
# a02 seq=4 : find a parquet engine that has a prebuilt wheel for this old glibc.
# seq=3 failed: "pyarrow>=16" resolved to a version with no manylinux_2_17 wheel,
# pip fell back to building from source and the build deps failed.
# Strategy: --only-binary=:all: so we never compile; try newest-to-oldest pyarrow,
# then fastparquet (pandas falls back to it automatically).
export LC_ALL=C
NHP=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
NHPIP=/data1/home/$USER/miniconda3/envs/nh_final/bin/pip

echo "=== A SYSTEM ==="
ldd --version 2>&1 | head -1
$NHPIP --version 2>&1
$NHP -c "import sys,platform;print('py',sys.version.split()[0],platform.machine())"

echo "=== B WHICH WHEELS EXIST (download only, no install) ==="
for V in 21.0.0 20.0.0 19.0.1 18.1.0 17.0.0 16.1.0; do
  OUT=$(timeout 180 $NHPIP download --no-deps --only-binary=:all: --dest /tmp/a02_wheelprobe \
        "pyarrow==$V" 2>&1 | tail -2)
  if echo "$OUT" | grep -qi "Saved\|Downloading\|File was already downloaded"; then
    echo "  pyarrow $V : WHEEL AVAILABLE"
  else
    echo "  pyarrow $V : no compatible wheel"
  fi
done
ls /tmp/a02_wheelprobe 2>/dev/null | head -5

echo "=== C INSTALL BEST AVAILABLE pyarrow (binary only) ==="
INSTALLED=""
for V in 21.0.0 20.0.0 19.0.1 18.1.0 17.0.0 16.1.0; do
  if timeout 300 $NHPIP install --no-cache-dir --only-binary=:all: --no-deps "pyarrow==$V" 2>&1 | tail -3 | grep -qi "Successfully installed"; then
    echo "  installed pyarrow==$V"
    INSTALLED=$V
    break
  fi
done
[ -z "$INSTALLED" ] && echo "  no pyarrow wheel installable"

echo "=== D FALLBACK: fastparquet (pandas auto-falls back to it) ==="
if [ -z "$INSTALLED" ]; then
  timeout 300 $NHPIP install --no-cache-dir --only-binary=:all: fastparquet 2>&1 | tail -4
fi

echo "=== E VERSIONS AFTER (numpy/pandas/torch MUST be unchanged) ==="
$NHP -c "
import importlib
for m in ['numpy','pandas','torch']:
    print('  ',m,importlib.import_module(m).__version__)
for m in ['pyarrow','fastparquet']:
    try:
        print('  ',m,importlib.import_module(m).__version__)
    except Exception as e:
        print('  ',m,'MISSING')
" 2>&1

echo "=== F FUNCTIONAL: parquet round-trip through whatever engine works ==="
$NHP -c "
import pandas as pd, numpy as np, tempfile, os
df = pd.DataFrame({'datetime_utc': pd.date_range('2020-01-01', periods=7, freq='h'),
                   'q_cms': np.arange(7, dtype='float64'),
                   'stage_m': np.arange(7, dtype='float64')/3})
p = os.path.join(tempfile.gettempdir(),'a02_probe.parquet')
df.to_parquet(p, index=False)
back = pd.read_parquet(p, columns=['datetime_utc','q_cms','stage_m'])
assert back.shape == (7,3), back.shape
assert np.allclose(back['stage_m'].to_numpy(), df['stage_m'].to_numpy())
print('   round-trip OK', back.shape, back['stage_m'].dtype)
" 2>&1 | tail -6

echo "=== G LANDING SITE ==="
ls -la ~/nature_1st_a02.tar.gz 2>&1 || echo "  tarball not uploaded yet"
