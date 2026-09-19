"""Generate the Stage-3 configs from the frozen 27-attribute base config (PREREG_20260916 section 2.2 / section 9).

Adapted from precip_swap2_daily_2026_09/hpc_deploy/make_pswap2_configs.py (sha256[:16] a46610d59e73aed4). Only these
keys may differ from the base and the script asserts it: experiment_name, seed, forcings, run_dir, data_dir,
{train,test,validation}_basin_file, dynamic_inputs, train_start_date, train_end_date, test_start_date, test_end_date,
plus epochs for the E3 60-epoch arms (declared contract-external control) and for the smoke configs.
Written configs (default arm set):
  E1  pswap3_win_imerg_e18 / pswap3_win_imerg_local / pswap3_win_gsmap_utc / pswap3_shift1_daymet   x seeds 100/200/300
  E2  pswap3_syn_ln035 / pswap3_syn_ln070 / pswap3_syn_ln140                                        x seeds 100/200/300
  E3  pswap3_ep60_ref_daymet (forcing daymet) / pswap3_ep60_era5l_refday (forcing era5l_refday), epochs 60, x 3 seeds
  opt pswap3_win_imerg_tau32 (--with-tau32)
  smoke: one 1-epoch 5-basin config per NEW forcing product (+ daymet)
Usage (HPC login node): python make_pswap3_configs.py [--with-tau32]
Local dry run:          python make_pswap3_configs.py --src <base.yml> --dst <dir> [--with-tau32]
The dry run writes the same texts (HPC absolute paths inside) so that the config set can be hashed before shipping.
Written with a file-write tool (not a heredoc); the only backslashes are ordinary string escapes.
"""
import argparse
import hashlib
import json
import pathlib
import sys

SRC_DEFAULT = pathlib.PurePosixPath('/data1/home/sunyiq/attr_swap_daily_2026_09/configs/attrswap_ref27_parity_s900.yml')
ROOT = pathlib.PurePosixPath('/data1/home/sunyiq/precip_swap3_daily_2026_09')   # PurePosixPath: identical text on Windows dry runs (audit B-1)
BASE_SHA16 = '33bfcc279b213848'   # PREREG_20260916 section 2.2 base config
OLD, NEW = 'attr_swap_daily_2026_09', 'precip_swap3_daily_2026_09'
DATES = {'train_start_date': '01/10/2004', 'train_end_date': '30/09/2013',
         'test_start_date': '01/10/1999', 'test_end_date': '30/09/2004'}
DYN_OLD = ['PRCP(mm/day)', 'Tmin(C)', 'Tmax(C)', 'SRAD(W/m2)', 'Vp(Pa)']
DYN_NEW = ['prcp(mm/day)', 'tmin(C)', 'tmax(C)', 'srad(W/m2)', 'vp(Pa)']
SEEDS = (100, 200, 300)
E1 = {'pswap3_win_imerg_e18': 'imerg_e18', 'pswap3_win_imerg_local': 'imerg_local',
      'pswap3_win_gsmap_utc': 'gsmap_utc', 'pswap3_shift1_daymet': 'daymet_shift1'}
E1_OPT = {'pswap3_win_imerg_tau32': 'imerg_tau32'}
R2_ARMS = {'pswap3_win_imerg_refday': 'imerg_refday', 'pswap3_win_imerg_utc': 'imerg_utc', 'pswap3_win_gsmap_refday': 'gsmap_refday'}  # reserve R2 (V14 fail)
E2 = {'pswap3_syn_ln035': 'syn_ln035', 'pswap3_syn_ln070': 'syn_ln070', 'pswap3_syn_ln140': 'syn_ln140'}
R1_ARMS = {'pswap3_syn_ln018': 'syn_ln018'}   # reserve R1 (PREREG 4.2): min C 0.120 > 0.05 -> sigma = 0.175, added 2026-09-18
E3 = {'pswap3_ep60_ref_daymet': 'daymet', 'pswap3_ep60_era5l_refday': 'era5l_refday'}
EP60 = 60
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


def build(src_text, dst, name, product, seed, run_dir, epochs=None, basin_file=None):
    src = src_text.splitlines(keepends=True)
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
    if epochs is None:
        assert 'epochs' not in changed, name + ': epochs changed without request'
    text = ''.join(out)
    with open(dst / (name + '.yml'), 'w', encoding='utf-8', newline=chr(10)) as fh:  # LF on every platform (audit B-1)
        fh.write(text)
    return sorted(changed), hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=str(SRC_DEFAULT))
    ap.add_argument('--dst', default=str(ROOT / 'configs'))
    ap.add_argument('--with-tau32', action='store_true')
    ap.add_argument('--with-r2', action='store_true', help='reserve R2: V14 failed, retrain the three Stage-2 window arms in this root')
    ap.add_argument('--r1-only', action='store_true', help='reserve R1: write ONLY the syn_ln018 arm + smoke configs and merge them into the existing manifest (nothing else is rewritten)')
    a = ap.parse_args()
    src_text = pathlib.Path(a.src).read_text()
    got = hashlib.sha256(src_text.encode('utf-8')).hexdigest()[:16]
    assert got == BASE_SHA16, 'base config changed: %s != %s' % (got, BASE_SHA16)
    dst = pathlib.Path(a.dst)
    dst.mkdir(parents=True, exist_ok=True)
    for d in DYN_OLD:
        assert ('- ' + d) in src_text, 'base config lacks ' + d
    manifest = {'base_sha16': hashlib.sha256(src_text.encode('utf-8')).hexdigest()[:16], 'configs': {}}
    mp = dst / 'configs_manifest.json'
    if a.r1_only:
        assert mp.exists(), 'R1 needs the manifest of the original submission'
        manifest = json.loads(mp.read_text(encoding='utf-8'))
        assert manifest['base_sha16'] == BASE_SHA16
        arms = dict(R1_ARMS)
    else:
        arms = dict(E1)
        if a.with_tau32:
            arms.update(E1_OPT)
        if a.with_r2:
            arms.update(R2_ARMS)
        arms.update(E2)
    n = 0
    for name, product in arms.items():
        for s in SEEDS:
            cfg = name + '_s' + str(s)
            ch, h = build(src_text, dst, cfg, product, s, str(ROOT / 'runs'))
            manifest['configs'][cfg] = dict(forcing=product, seed=s, epochs=30, changed=ch, sha16=h)
            print(cfg + '.yml forcing=' + product + ' changed=' + str(ch))
            n += 1
    for name, product in ({} if a.r1_only else E3).items():
        for s in SEEDS:
            cfg = name + '_s' + str(s)
            ch, h = build(src_text, dst, cfg, product, s, str(ROOT / 'runs'), epochs=EP60)
            manifest['configs'][cfg] = dict(forcing=product, seed=s, epochs=EP60, changed=ch, sha16=h)
            print(cfg + '.yml forcing=' + product + ' epochs=60 changed=' + str(ch))
            n += 1
    b5 = str(ROOT / 'basin_lists' / 'basins_5.txt')
    smoke_products = sorted(arms.values()) if a.r1_only else ['daymet'] + sorted((set(arms.values()) | set(E3.values())) - {'daymet'})  # explicit parentheses (audit B-10)
    for p in smoke_products:
        cfg = 'pswap3_smoke_' + p
        ch, h = build(src_text, dst, cfg, p, 100, str(ROOT / 'runs_smoke'), epochs=1, basin_file=b5)
        manifest['configs'][cfg] = dict(forcing=p, seed=100, epochs=1, smoke=True, changed=ch, sha16=h)
        print(cfg + '.yml changed=' + str(ch))
    mp.write_text(json.dumps(manifest, indent=1), encoding='utf-8')
    print('wrote %d arm configs + %d smoke configs into %s' % (n, len(smoke_products), dst))
    return 0


if __name__ == '__main__':
    sys.exit(main())
