"""Build the shadow Maurer forcing directory on the HPC and make it byte-identical to the local (baseline) copy.

Local facts (2026-09-05): the HPC and local CAMELS copies are identical (LF, per-directory sha256) for all 674
streamflow files, the 7 attribute files and 14 of 18 Maurer HUC directories. The 4 remaining HUC dirs differ in
exactly one file each and only in line 4 (the header): the local copies were fixed on 2026-06-16 15:12 (before
the 8-seed baseline was trained) from the malformed CAMELS header
    'dayl(s) prcp(mm/day) srad(W/m2) swe(mm) tmax(C) tmin(C) vp(Pa)'
to  'Year Mnth Day Hr<TAB>Dayl(s)<TAB>PRCP(mm/day)<TAB>SRAD(W/m2)<TAB>SWE(mm)<TAB>Tmax(C)<TAB>Tmin(C)<TAB>Vp(Pa)'.
This script symlinks every Maurer file read-only from the HPC source, except those 4 basins which are copied with
the same one-line header fix, then verifies each HUC dir against the local per-dir hash (CR-stripped recipe).

Usage: python hpc_fix_maurer_headers.py <src maurer dir> <dst shadow maurer dir>
"""
import hashlib
import os
import pathlib
import sys

SRC = pathlib.Path(sys.argv[1]).resolve()
DST = pathlib.Path(sys.argv[2])
TAB = chr(9)
FIXED = ('Year Mnth Day Hr' + TAB + 'Dayl(s)' + TAB + 'PRCP(mm/day)' + TAB + 'SRAD(W/m2)' + TAB + 'SWE(mm)' + TAB +
         'Tmax(C)' + TAB + 'Tmin(C)' + TAB + 'Vp(Pa)').encode()
ORIG = b'dayl(s) prcp(mm/day) srad(W/m2) swe(mm) tmax(C) tmin(C) vp(Pa)'
FIX_BASINS = {'02108000', '05120500', '07067000', '09492400'}
EXPECTED = {  # local per-HUC combined hash (sha256 over 'sha256(file bytes without CR)  basin_mean_forcing/maurer/<huc>/<file>' lines)
    '01': '212d4adcb0f21689', '02': '59b0666bb3dbde86', '03': 'c94970cf20a9bd2e', '04': '35eb1cc59b70e6d9',
    '05': '01110312f5f3a9df', '06': '47510fb8c74ce954', '07': 'ecd471a053e8f615', '08': '536f2873384ab107',
    '09': '93305e931e5b2f7b', '10': 'dd4c242c3f1e5a1a', '11': '253c3d13f171ef31', '12': '787d8ea15ea279f5',
    '13': '557f4cf2bb78152b', '14': '64174ee436c241a8', '15': '765756a147cdf86f', '16': '1dd997ec3b9332ac',
    '17': 'fed6df09ffcebec2', '18': 'e0b6380773672575'}
CR = bytes([13])
LF = bytes([10])

DST.mkdir(parents=True, exist_ok=True)
n_link = n_fix = 0
for huc_dir in sorted(p for p in SRC.iterdir() if p.is_dir()):
    (DST / huc_dir.name).mkdir(exist_ok=True)
    for f in sorted(p for p in huc_dir.iterdir() if p.is_file()):
        dst = DST / huc_dir.name / f.name
        if dst.exists() or dst.is_symlink():
            dst.unlink()
        if f.name[:8] in FIX_BASINS:
            lines = f.read_bytes().split(LF)
            if lines[3] == ORIG:
                lines[3] = FIXED
                n_fix += 1
            elif lines[3] != FIXED:
                print(f'UNEXPECTED header in {f}: {lines[3]!r}')
            dst.write_bytes(LF.join(lines))
        else:
            os.symlink(str(f), str(dst))
            n_link += 1
print(f'symlinked {n_link} files, copied+header-fixed {n_fix} files')

ok = True
for huc_dir in sorted(p for p in DST.iterdir() if p.is_dir()):
    acc = hashlib.sha256()
    n = 0
    for f in sorted(p for p in huc_dir.iterdir() if p.is_file()):  # is_file follows symlinks
        h = hashlib.sha256(f.read_bytes().replace(CR, b'')).hexdigest()
        acc.update(f'{h}  basin_mean_forcing/maurer/{huc_dir.name}/{f.name}\n'.encode())
        n += 1
    got = acc.hexdigest()[:16]
    exp = EXPECTED.get(huc_dir.name, '?')
    flag = 'MATCH' if got == exp else 'MISMATCH'
    ok &= got == exp
    print(f'maurer/{huc_dir.name} {n} {got} expected {exp} {flag}')
print('MAURER SHADOW IDENTICAL TO LOCAL: ' + ('YES' if ok else 'NO'))
sys.exit(0 if ok else 1)
