"""Generate the Stage-2 configs from the frozen 27-attribute base config (PREREG_20260911 section 2.2).

Adapted from hpc_deploy/stage1_originals/make_pswap_configs.py (sha256[:16] 54d67cf34a3d1af7). Only these keys may
differ from the base and the script asserts it: experiment_name, seed, forcings, run_dir, data_dir,
{train,test,validation}_basin_file, dynamic_inputs, train_start_date, train_end_date, test_start_date, test_end_date,
plus epochs for the smoke configs. Written configs: 8 ref_daymet + 8 arms x 3 seeds + 9 smoke configs.
Runs on the HPC login node inside the landing directory. No backslash literals are used anywhere in this file.
"""
import pathlib
import sys

SRC = pathlib.Path('/data1/home/sunyiq/attr_swap_daily_2026_09/configs/attrswap_ref27_parity_s900.yml')
ROOT = pathlib.Path('/data1/home/sunyiq/precip_swap2_daily_2026_09')
DST = ROOT / 'configs'
OLD, NEW = 'attr_swap_daily_2026_09', 'precip_swap2_daily_2026_09'
DATES = {'train_start_date': '01/10/2004', 'train_end_date': '30/09/2013',
         'test_start_date': '01/10/1999', 'test_end_date': '30/09/2004'}
DYN_OLD = ['PRCP(mm/day)', 'Tmin(C)', 'Tmax(C)', 'SRAD(W/m2)', 'Vp(Pa)']
DYN_NEW = ['prcp(mm/day)', 'tmin(C)', 'tmax(C)', 'srad(W/m2)', 'vp(Pa)']
PRODUCTS = ['imerg_local', 'imerg_uncal', 'imerg_utc', 'gsmap_local', 'gsmap_uncal', 'persiann', 'chirps', 'era5l_precip2']
ARM_STEM = {p: 'pswap2_armP_' + (p if p != 'era5l_precip2' else 'era5l') for p in PRODUCTS}
ALLOWED = {'experiment_name', 'seed', 'forcings', 'run_dir', 'data_dir', 'train_basin_file', 'test_basin_file',
           'validation_basin_file', 'dynamic_inputs', 'train_start_date', 'train_end_date', 'test_start_date',
           'test_end_date', 'epochs'}


def key_of(line):
    if line[:1].isspace() or line.startswith('-') or ':' not in line:
        return None
    k = line.split(':', 1)[0].strip()
    return k if k.replace('_', '').isalnum() else None


def set_scalar(lines, key, value):
    for i, line in enumerate(lines):
        if key_of(line) == key:
            lines[i] = key + ': ' + str(value) + '\n'
            return True
    return False


def set_list(lines, key, values):
    """Replace the '- item' lines that follow 'key:' with the given values (same count)."""
    for i, line in enumerate(lines):
        if key_of(line) == key:
            j = i + 1
            items = []
            while j < len(lines) and lines[j].lstrip().startswith('-'):
                items.append(j)
                j += 1
            assert len(items) == len(values), (key, len(items), len(values))
            for idx, v in zip(items, values):
                lines[idx] = '- ' + v + '\n'
            return True
    return False


def build(name, product, seed, run_dir, epochs=None, basin_file=None):
    src = SRC.read_text().splitlines(keepends=True)
    out = [l.replace(OLD, NEW) for l in src]
    assert set_scalar(out, 'experiment_name', name), 'experiment_name'
    assert set_scalar(out, 'seed', seed), 'seed'
    assert set_scalar(out, 'run_dir', run_dir), 'run_dir'
    assert set_list(out, 'forcings', [product]), 'forcings'
    assert set_list(out, 'dynamic_inputs', DYN_NEW), 'dynamic_inputs'
    for k, v in DATES.items():
        assert set_scalar(out, k, v), k
    if epochs is not None:
        assert set_scalar(out, 'epochs', epochs), 'epochs'
    if basin_file:
        for k in ('train_basin_file', 'test_basin_file', 'validation_basin_file'):
            assert set_scalar(out, k, basin_file), k
    assert len(out) == len(src), name + ': line count changed'
    changed, last = set(), None
    for a, b in zip(src, out):
        k = key_of(a)
        if k:
            last = k
        if a != b:
            changed.add(k or last)
    bad = changed - ALLOWED
    assert not bad, name + ': unexpected changed keys ' + str(sorted(bad))
    (DST / (name + '.yml')).write_text(''.join(out))
    return sorted(changed)


def main():
    DST.mkdir(parents=True, exist_ok=True)
    src = SRC.read_text().splitlines(keepends=True)
    # sanity: the base really carries the capitalised Maurer names we are replacing
    joined = ''.join(src)
    for d in DYN_OLD:
        assert ('- ' + d) in joined, 'base config lacks ' + d
    n = 0
    for s in range(100, 900, 100):
        ch = build('ref_daymet_s' + str(s), 'daymet', s, str(ROOT / 'runs'))
        print('ref_daymet_s%d.yml changed=%s' % (s, ch))
        n += 1
    for p in PRODUCTS:
        for s in (100, 200, 300):
            name = ARM_STEM[p] + '_s' + str(s)
            ch = build(name, p, s, str(ROOT / 'runs'))
            print(name + '.yml forcing=' + p + ' changed=' + str(ch))
            n += 1
    b5 = str(ROOT / 'basin_lists' / 'basins_5.txt')
    for p in ['daymet'] + PRODUCTS:
        ch = build('pswap2_smoke_' + p, p, 100, str(ROOT / 'runs_smoke'), epochs=1, basin_file=b5)
        print('pswap2_smoke_' + p + '.yml changed=' + str(ch))
    print('wrote %d arm configs + %d smoke configs into %s' % (n, 1 + len(PRODUCTS), DST))
    return 0


if __name__ == '__main__':
    sys.exit(main())
