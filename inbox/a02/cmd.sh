#!/bin/bash
# a02 seq=3 : install pyarrow into nh_final via pip (user-authorised 2026-08-07)
# Review finding #6: pip is preferred over conda here -- conda on CentOS 7 /
# GLIBC 2.17 would fall back to an old pyarrow built against numpy 1.x and could
# downgrade numpy. pip picks a manylinux2014 wheel and touches nothing else.
export LC_ALL=C
NHP=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
NHPIP=/data1/home/$USER/miniconda3/envs/nh_final/bin/pip

echo "=== A BEFORE ==="
$NHP -c "
import importlib
for m in ['numpy','pandas','torch']:
    print('  ',m,importlib.import_module(m).__version__)
try:
    import pyarrow; print('   pyarrow',pyarrow.__version__)
except ImportError:
    print('   pyarrow MISSING')
" 2>&1

echo "=== B INSTALL (pip) ==="
timeout 900 $NHPIP install --no-cache-dir "pyarrow>=16" 2>&1 | tail -12

echo "=== C AFTER (numpy/pandas/torch versions MUST be unchanged) ==="
$NHP -c "
import importlib
for m in ['numpy','pandas','torch']:
    print('  ',m,importlib.import_module(m).__version__)
import pyarrow; print('   pyarrow',pyarrow.__version__)
" 2>&1

echo "=== D FUNCTIONAL CHECK: pandas parquet round-trip ==="
$NHP -c "
import pandas as pd, numpy as np, tempfile, os
df = pd.DataFrame({'datetime_utc': pd.date_range('2020-01-01', periods=5, freq='h'),
                   'q_cms': np.arange(5, dtype='float64'),
                   'stage_m': np.arange(5, dtype='float64')/3})
p = os.path.join(tempfile.gettempdir(), 'a02_probe.parquet')
df.to_parquet(p, index=False)
back = pd.read_parquet(p, columns=['datetime_utc','q_cms','stage_m'])
assert back.shape == (5,3), back.shape
assert np.allclose(back['stage_m'].to_numpy(), df['stage_m'].to_numpy())
os.remove(p)
print('   parquet round-trip OK', back.shape)
" 2>&1

echo "=== E LANDING SITE (has the tarball arrived yet?) ==="
ls -la ~/nature_1st_a02.tar.gz 2>&1 || echo "  tarball not uploaded yet"
