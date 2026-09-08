"""Generate the nine forcing-swap configs (plus one smoke config) from the frozen attribute-swap configs.

Only these lines may change w.r.t. the base config, and the script asserts it:
  experiment_name, seed, forcings (and its list item), run_dir, data_dir, {train,test,validation}_basin_file,
  epochs (smoke config only).
Everything else -- model, hidden size, dropout, forget bias, sequence length, batch size, learning rates, loss,
periods, static attributes -- is inherited byte-identically, so the arms differ from the frozen contract by the
forcing product (and, for armE23, by the already-adjudicated 23-attribute set) alone.
"""
import pathlib
import re
import sys

SRC = pathlib.Path('/data1/home/sunyiq/attr_swap_daily_2026_09/configs')
DST = pathlib.Path('/data1/home/sunyiq/forcing_swap_daily_2026_09/configs')
BASE27 = SRC / 'attrswap_ref27_parity_s900.yml'
BASE23 = SRC / 'attrswap_armA_chn23_s100.yml'
OLD, NEW = 'attr_swap_daily_2026_09', 'forcing_swap_daily_2026_09'

ARMS = [('fswap_armE27', BASE27, 'era5l_caravan', [100, 200, 300]),
        ('fswap_armE23', BASE23, 'era5l_caravan', [100, 200, 300]),
        ('fswap_armEP', BASE27, 'era5l_caravan_pmaurer', [100, 200, 300])]
ALLOWED = {'experiment_name', 'seed', 'forcings', 'run_dir', 'data_dir', 'train_basin_file', 'test_basin_file',
           'validation_basin_file', 'epochs'}


def set_scalar(lines, key, value):
    for i, l in enumerate(lines):
        if re.match(rf'^{re.escape(key)}\s*:', l):
            lines[i] = f'{key}: {value}\n'
            return True
    return False


def set_forcing(lines, product):
    for i, l in enumerate(lines):
        if re.match(r'^forcings\s*:', l):
            if '[' in l:
                lines[i] = f"forcings: ['{product}']\n"
            else:
                assert lines[i + 1].lstrip().startswith('-'), lines[i + 1]
                lines[i + 1] = re.sub(r'-\s*\S+', f'- {product}', lines[i + 1])
            return True
    return False


def key_of(line):
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:', line)
    return m.group(1) if m else None


def build(base, name, product, seed, run_dir, epochs=None):
    src = base.read_text().splitlines(keepends=True)
    out = [l.replace(OLD, NEW) for l in src]
    assert set_scalar(out, 'experiment_name', name), 'experiment_name not found'
    assert set_scalar(out, 'seed', seed), 'seed not found'
    assert set_scalar(out, 'run_dir', run_dir), 'run_dir not found'
    assert set_forcing(out, product), 'forcings not found'
    if epochs is not None:
        assert set_scalar(out, 'epochs', epochs), 'epochs not found'
    assert len(out) == len(src), f'{name}: line count changed {len(src)} -> {len(out)}'
    changed, last_key = set(), None
    for a, b in zip(src, out):
        k = key_of(a)
        if k:
            last_key = k
        if a != b:
            changed.add(k or last_key)
    bad = changed - ALLOWED
    assert not bad, f'{name}: unexpected changed keys {sorted(bad)}'
    (DST / f'{name}.yml').write_text(''.join(out))
    return sorted(changed)


def main():
    DST.mkdir(parents=True, exist_ok=True)
    root = pathlib.Path(f'/data1/home/sunyiq/{NEW}')
    n = 0
    for stem, base, product, seeds in ARMS:
        for s in seeds:
            ch = build(base, f'{stem}_s{s}', product, s, str(root / 'runs'))
            print(f'{stem}_s{s}.yml  base={base.name}  forcing={product}  changed={ch}')
            n += 1
    ch = build(BASE27, 'fswap_smoke', 'era5l_caravan', 100, str(root / 'runs_smoke'), epochs=1)
    for f in ['train_basin_file', 'test_basin_file', 'validation_basin_file']:
        lines = (DST / 'fswap_smoke.yml').read_text().splitlines(keepends=True)
        assert set_scalar(lines, f, str(root / 'basin_lists' / 'basins_5.txt'))
        (DST / 'fswap_smoke.yml').write_text(''.join(lines))
    print(f'fswap_smoke.yml  changed={ch} + 5-basin lists')
    print(f'WROTE {n} arm configs + 1 smoke config into {DST}')


if __name__ == '__main__':
    sys.exit(main())
