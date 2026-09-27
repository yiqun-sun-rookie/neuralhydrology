"""Generate the GPM-era contract configs from the frozen 27-attribute base config (same base as Stages 2/3).

Adapted from precip_swap3 make_pswap3_configs.py (sha256[:16] 7c6c84b897aac5ec). Only these keys may differ from the
base and the script asserts it: experiment_name, seed, forcings, run_dir, data_dir, {train,test,validation}_basin_file,
dynamic_inputs, train_start_date, train_end_date, test_start_date, test_end_date, plus epochs for the smoke configs.
Arms (30 epochs, contract of this stage):
  pswap4_ref_daymet4                x seeds 100..800 (8)   forcing daymet4 (Daymet V4 reference built by build_shadow4.py)
  pswap4_armG_<product>             x seeds 100/200/300    six Stage-2 product definitions re-extracted for 2014-2023
  smoke: pswap4_smoke_<forcing>     1 epoch, 5 basins, seed 100, for daymet4 and every product
configs/arms.txt lists the 26 arm configs in submission order (reference first) for the array job.
Usage (HPC login node): python make_pswap4_configs.py
Local dry run:          python make_pswap4_configs.py --src <base.yml> --dst <dir>
No backslash literals anywhere in this file.
"""
import argparse
import hashlib
import json
import pathlib
import sys

SRC_DEFAULT = pathlib.PurePosixPath('/data1/home/sunyiq/attr_swap_daily_2026_09/configs/attrswap_ref27_parity_s900.yml')
ROOT = pathlib.PurePosixPath('/data1/home/sunyiq/precip_swap4_gpm_daily_2026_09')
BASE_SHA16 = '33bfcc279b213848'
OLD, NEW = 'attr_swap_daily_2026_09', 'precip_swap4_gpm_daily_2026_09'
DATES = {'train_start_date': '01/10/2015', 'train_end_date': '30/09/2020',
         'test_start_date': '01/10/2020', 'test_end_date': '30/09/2023'}
DYN_OLD = ['PRCP(mm/day)', 'Tmin(C)', 'Tmax(C)', 'SRAD(W/m2)', 'Vp(Pa)']
DYN_NEW = ['prcp(mm/day)', 'tmin(C)', 'tmax(C)', 'srad(W/m2)', 'vp(Pa)']
REF_SEEDS = (100, 200, 300, 400, 500, 600, 700, 800)
ARM_SEEDS = (100, 200, 300)
PRODUCTS = ['gsmap_refday', 'imerg_utc', 'imerg_refday', 'chirps', 'era5l_refday', 'imerg_uncal_refday']
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
            lines[i] = key + ': ' + str(value) + chr(10)
            return True
    return False


def set_list(lines, key, values):
    for i, line in enumerate(lines):
        if key_of(line) == key:
            j = i + 1
            items = []
            while j < len(lines) and lines[j].lstrip().startswith('-'):
                items.append(j)
                j += 1
            assert len(items) == len(values), (key, len(items), len(values))
            for idx, v in zip(items, values):
                lines[idx] = '- ' + v + chr(10)
            return True
    return False


def build(src_text, dst, name, forcing, seed, run_dir, basin_file, epochs=None):
    src = src_text.splitlines(keepends=True)
    out = [l.replace(OLD, NEW) for l in src]
    assert set_scalar(out, 'experiment_name', name), 'experiment_name'
    assert set_scalar(out, 'seed', seed), 'seed'
    assert set_scalar(out, 'run_dir', run_dir), 'run_dir'
    assert set_list(out, 'forcings', [forcing]), 'forcings'
    assert set_list(out, 'dynamic_inputs', DYN_NEW), 'dynamic_inputs'
    for k, v in DATES.items():
        assert set_scalar(out, k, v), k
    for k in ('train_basin_file', 'test_basin_file', 'validation_basin_file'):
        assert set_scalar(out, k, basin_file), k
    if epochs is not None:
        assert set_scalar(out, 'epochs', epochs), 'epochs'
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
    if epochs is None:
        assert 'epochs' not in changed, name + ': epochs changed without request'
    text = ''.join(out)
    assert 'attr_swap_daily_2026_09' not in text, name + ': old root left in config'
    with open(dst / (name + '.yml'), 'w', encoding='utf-8', newline=chr(10)) as fh:
        fh.write(text)
    return sorted(changed), hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=str(SRC_DEFAULT))
    ap.add_argument('--dst', default=str(ROOT / 'configs'))
    a = ap.parse_args()
    src_text = pathlib.Path(a.src).read_text()
    got = hashlib.sha256(src_text.encode('utf-8')).hexdigest()[:16]
    assert got == BASE_SHA16, 'base config changed: %s != %s' % (got, BASE_SHA16)
    for d in DYN_OLD:
        assert ('- ' + d) in src_text, 'base config lacks ' + d
    dst = pathlib.Path(a.dst)
    dst.mkdir(parents=True, exist_ok=True)
    b132 = str(ROOT / 'basin_lists' / 'basins_132.txt')
    b5 = str(ROOT / 'basin_lists' / 'basins_5.txt')
    manifest = {'base_sha16': got, 'dates': DATES, 'configs': {}}
    arms = []
    for s in REF_SEEDS:
        arms.append(('pswap4_ref_daymet4_s%d' % s, 'daymet4', s))
    for p in PRODUCTS:
        for s in ARM_SEEDS:
            arms.append(('pswap4_armG_%s_s%d' % (p, s), p, s))
    for cfg, forcing, s in arms:
        ch, h = build(src_text, dst, cfg, forcing, s, str(ROOT / 'runs'), b132)
        manifest['configs'][cfg] = dict(forcing=forcing, seed=s, epochs=30, changed=ch, sha16=h)
    for forcing in ['daymet4'] + PRODUCTS:
        cfg = 'pswap4_smoke_' + forcing
        ch, h = build(src_text, dst, cfg, forcing, 100, str(ROOT / 'runs_smoke'), b5, epochs=1)
        manifest['configs'][cfg] = dict(forcing=forcing, seed=100, epochs=1, smoke=True, changed=ch, sha16=h)
    with open(dst / 'arms.txt', 'w', encoding='utf-8', newline=chr(10)) as fh:
        fh.write(chr(10).join(c for c, _, _ in arms) + chr(10))
    (dst / 'configs_manifest.json').write_text(json.dumps(manifest, indent=1), encoding='utf-8')
    print('wrote %d arm configs + %d smoke configs + arms.txt into %s' % (len(arms), 1 + len(PRODUCTS), dst))
    return 0


if __name__ == '__main__':
    sys.exit(main())
