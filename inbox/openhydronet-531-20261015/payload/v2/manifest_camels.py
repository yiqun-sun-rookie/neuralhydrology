"""Per-file SHA-256 manifest of the CAMELS-US files the ID18 LSTM protocol reads (stdlib only; runs locally and on the HPC).

usage: python manifest_camels.py <camels_us_dir> <basin_list.txt> <out.tsv>
Files per basin: basin_mean_forcing/maurer/**/<id>_*_forcing_leap.txt and usgs_streamflow/**/<id>_streamflow_qc.txt;
plus camels_attributes_v2.0/camels_{clim,geol,hydro,name,soil,topo,vege}.txt.
"""
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
basins = [b.strip() for b in Path(sys.argv[2]).read_text().split() if b.strip()]
rows = []
for b in basins:
    b = b.replace('camels_', '')
    for pat in (f'basin_mean_forcing/maurer/**/{b}_*_forcing_leap.txt', f'usgs_streamflow/**/{b}_streamflow_qc.txt'):
        hits = sorted(root.glob(pat))
        if len(hits) != 1:
            rows.append((f'{b}:{pat}', f'HITS={len(hits)}', 0))
            continue
        data = hits[0].read_bytes()
        rows.append((hits[0].relative_to(root).as_posix(), hashlib.sha256(data).hexdigest(), len(data)))
for n in ('clim', 'geol', 'hydro', 'name', 'soil', 'topo', 'vege'):
    p = root / 'camels_attributes_v2.0' / f'camels_{n}.txt'
    data = p.read_bytes() if p.is_file() else b''
    rows.append((p.relative_to(root).as_posix(), hashlib.sha256(data).hexdigest() if data else 'MISSING', len(data)))
Path(sys.argv[3]).write_text('\n'.join('\t'.join(map(str, r)) for r in rows) + '\n', encoding='utf-8', newline='\n')
tot = hashlib.sha256('\n'.join(f'{a}\t{b}' for a, b, _ in rows).encode()).hexdigest()
print('files', len(rows), 'bytes', sum(r[2] for r in rows), 'bad', sum(1 for r in rows if r[1].startswith('HITS') or r[1] == 'MISSING'), 'overall', tot)
