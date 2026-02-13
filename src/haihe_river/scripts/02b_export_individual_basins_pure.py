#!/usr/bin/env python3
"""
�?pyshp 导出：根据筛选清单（CSV，含 HYBAS_ID、basin_id）从 HydroBASINS 原始 shp 导出单体 GeoJSON�?

用法�?
  conda run -n neuralhydrology_gpu python src/haihe_river/scripts/02b_export_individual_basins_pure.py \
    --hybas-shp data/haihe/hydrobasins/source/hybas_as_lev09_v1c.shp \
    --list-csv data/haihe/hydrobasins/lev9/haihe_hybas_lev9_list.csv \
    --out-dir data/haihe/basins_individual
"""

import argparse
from pathlib import Path
import json
import shapefile  # pyshp
import pandas as pd
from tqdm import tqdm


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--hybas-shp', required=True)
    ap.add_argument('--list-csv', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(args.list_csv)
    if 'HYBAS_ID' not in df.columns:
        raise SystemExit('list csv 缺少 HYBAS_ID')
    ids = set(int(x) for x in df['HYBAS_ID'].dropna().astype(int).tolist())
    id_to_basin = {}
    if 'basin_id' in df.columns:
        id_to_basin = {int(r.HYBAS_ID): str(r.basin_id) for _, r in df[['HYBAS_ID','basin_id']].iterrows()}

    r = shapefile.Reader(args.hybas_shp)
    fields = [f[0] for f in r.fields[1:]]
    idx_id = fields.index('HYBAS_ID')

    written = 0
    with open(out_dir / 'basin_list.txt', 'w', encoding='utf-8') as bl:
        for sr in tqdm(r.shapeRecords(), desc='导出单体'):
            hyid = int(sr.record[idx_id])
            if hyid not in ids:
                continue
            basin_id = id_to_basin.get(hyid, f'HB{hyid}')
            geom = sr.shape.__geo_interface__
            feat = {
                'type': 'Feature',
                'geometry': geom,
                'properties': {'basin_id': basin_id, 'HYBAS_ID': hyid}
            }
            gj = {'type': 'FeatureCollection', 'features': [feat]}
            fp = out_dir / f'{basin_id}.geojson'
            with open(fp, 'w', encoding='utf-8') as f:
                json.dump(gj, f)
            bl.write(f'{basin_id}\n')
            written += 1

    print('[OK] 输出目录:', out_dir, '数量:', written)


if __name__ == '__main__':
    main()


