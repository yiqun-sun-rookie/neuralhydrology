#!/usr/bin/env python3
"""
�?pyshp+shapely 版本：不依赖 GDAL/PROJ，筛�?HydroBASINS 在海河边界内的子流域，并导出 CSV（含 basin_id �?SUB_AREA）�?
只用于面积统计与快速预选级别�?
"""
import argparse
from pathlib import Path
import shapefile  # pyshp
from shapely.geometry import shape as shp_shape
from shapely.ops import unary_union
import pandas as pd


def read_union_polygon(shp_path: Path):
    r = shapefile.Reader(str(shp_path))
    geoms = []
    for sr in r.shapeRecords():
        geom = shp_shape(sr.shape.__geo_interface__)
        if not geom.is_empty:
            geoms.append(geom)
    return unary_union(geoms)


def filter_hydrobasins(hybas_shp: Path, haihe_union, out_csv: Path, overlap_ratio_min: float = 0.05):
    r = shapefile.Reader(str(hybas_shp))
    fields = [f[0] for f in r.fields[1:]]
    # �?HYBAS_ID �?SUB_AREA 字段
    try:
        idx_id = fields.index('HYBAS_ID')
    except ValueError:
        raise SystemExit('HYBAS_ID not found')
    idx_area = fields.index('SUB_AREA') if 'SUB_AREA' in fields else None

    rows = []
    for sr in r.shapeRecords():
        geom = shp_shape(sr.shape.__geo_interface__)
        if geom.is_empty:
            continue
        if not geom.intersects(haihe_union):
            continue
        inter = geom.intersection(haihe_union)
        if inter.is_empty:
            continue
        ratio = inter.area / geom.area if geom.area > 0 else 0.0
        if ratio < overlap_ratio_min:
            continue
        hyid = int(sr.record[idx_id])
        area = float(sr.record[idx_area]) if idx_area is not None else float('nan')
        rows.append({'basin_id': f'HB{hyid}', 'HYBAS_ID': hyid, 'SUB_AREA': area})

    df = pd.DataFrame(rows)
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out_csv, index=False, encoding='utf-8-sig')
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--haihe-shp', default='data/haihe/boundary/haihe_basin.shp')
    ap.add_argument('--hybas-shp', required=True)
    ap.add_argument('--out-csv', required=True)
    ap.add_argument('--overlap-ratio', type=float, default=0.05)
    args = ap.parse_args()

    haihe_union = read_union_polygon(Path(args.haihe_shp))
    df = filter_hydrobasins(Path(args.hybas_shp), haihe_union, Path(args.out_csv), args.overlap_ratio)
    print('[OK] 筛选数�?', len(df))


if __name__ == '__main__':
    main()


