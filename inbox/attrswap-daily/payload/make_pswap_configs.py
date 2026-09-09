"""Generate the six precipitation-swap configs plus one smoke config from the frozen 27-attribute config.

Only these keys may differ from the base, and the script asserts it: experiment_name, seed, forcings, run_dir,
data_dir, {train,test,validation}_basin_file, and epochs for the smoke config.
"""
import pathlib
import re

SRC = pathlib.Path('/data1/home/sunyiq/attr_swap_daily_2026_09/configs/attrswap_ref27_parity_s900.yml')
ROOT = pathlib.Path('/data1/home/sunyiq/precip_swap_daily_2026_09')
DST = ROOT / 'configs'
OLD, NEW = 'attr_swap_daily_2026_09', 'precip_swap_daily_2026_09'
ARMS = [('pswap_armP_chirps', 'chirps'), ('pswap_armP_era5l', 'era5l_precip')]
ALLOWED = {'experiment_name', 'seed', 'forcings', 'run_dir', 'data_dir', 'train_basin_file', 'test_basin_file',
           'validation_basin_file', 'epochs'}


def set_scalar(lines, key, value):
    for i, line in enumerate(lines):
        if re.match(r'^' + re.escape(key) + r'\s*:', line):
            lines[i] = key + ': ' + str(value) + '\n'
            return True
    return False


def set_forcing(lines, product):
    for i, line in enumerate(lines):
        if re.match(r'^forcings\s*:', line):
            if '[' in line:
                lines[i] = "forcings: ['" + product + "']\n"
            else:
                assert lines[i + 1].lstrip().startswith('-'), lines[i + 1]
                lines[i + 1] = re.sub(r'-\s*\S+', '- ' + product, lines[i + 1])
            return True
    return False


def key_of(line):
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:', line)
    return m.group(1) if m else None


def build(name, product, seed, run_dir, epochs=None, basin_file=None):
    src = SRC.read_text().splitlines(keepends=True)
    out = [l.replace(OLD, NEW) for l in src]
    assert set_scalar(out, 'experiment_name', name), 'experiment_name'
    assert set_scalar(out, 'seed', seed), 'seed'
    assert set_scalar(out, 'run_dir', run_dir), 'run_dir'
    assert set_forcing(out, product), 'forcings'
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
    n = 0
    for stem, product in ARMS:
        for s in (100, 200, 300):
            name = stem + '_s' + str(s)
            ch = build(name, product, s, str(ROOT / 'runs'))
            print(name + '.yml  forcing=' + product + '  changed=' + str(ch))
            n += 1
    ch = build('pswap_smoke', 'chirps', 100, str(ROOT / 'runs_smoke'), epochs=1,
               basin_file=str(ROOT / 'basin_lists' / 'basins_5.txt'))
    print('pswap_smoke.yml  changed=' + str(ch))
    print('wrote ' + str(n) + ' arm configs + 1 smoke config into ' + str(DST))


if __name__ == '__main__':
    main()
