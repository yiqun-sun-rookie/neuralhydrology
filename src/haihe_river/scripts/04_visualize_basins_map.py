#!/usr/bin/env python3
"""
脚本4: 预览海河 2471 个小流域在交互地图上（Folium），输出 HTML�?

用法�?
  conda run -n neuralhydrology_gpu python src/haihe_river/scripts/04_visualize_basins_map.py \
    --basins-dir data/haihe/basins_individual \
    --out-html results/06_haihe_river/figures/basins_map.html
"""

import os
import argparse
from pathlib import Path
import json
import folium


def load_first_center(basins_dir: Path):
    files = sorted(basins_dir.glob('*.geojson'))
    if not files:
        return 39.9, 116.4  # fallback Beijing approx
    with open(files[0], 'r', encoding='utf-8') as fp:
        obj = json.load(fp)
    # try feature geometry
    geom = None
    if obj.get('type') == 'FeatureCollection':
        feats = obj.get('features', [])
        if feats:
            geom = feats[0].get('geometry')
    elif obj.get('type') == 'Feature':
        geom = obj.get('geometry')
    else:
        geom = obj
    # compute centroid from first polygon ring
    try:
        coords = geom['coordinates'][0][0]
        lon = sum([c[0] for c in coords]) / len(coords)
        lat = sum([c[1] for c in coords]) / len(coords)
        return lat, lon
    except Exception:
        return 39.9, 116.4


def main():
    parser = argparse.ArgumentParser(description="Visualize Haihe sub-basins on a Folium map")
    parser.add_argument("--basins-dir", default="data/haihe/basins_individual", help="Directory with per-basin GeoJSON files")
    parser.add_argument('--out-html', default='results/06_haihe_river/figures/basins_map.html', help='输出 HTML 路径')
    args = parser.parse_args()

    basins_dir = Path(args.basins_dir)
    out_html = Path(args.out_html)
    out_html.parent.mkdir(parents=True, exist_ok=True)

    lat, lon = load_first_center(basins_dir)
    m = folium.Map(location=[lat, lon], zoom_start=6, tiles='OpenStreetMap')

    files = sorted(basins_dir.glob('*.geojson'))
    for i, f in enumerate(files, start=1):
        try:
            folium.GeoJson(
                data=str(f),
                name=f.stem,
                tooltip=f.stem,
                zoom_on_click=False,
                control=False,
                style_function=lambda x: {
                    'color': '#3388ff', 'weight': 1, 'fill': False, 'opacity': 0.6
                }
            ).add_to(m)
        except Exception:
            continue

    folium.LayerControl().add_to(m)
    m.save(str(out_html))
    print("[OK] Map exported:", out_html)


if __name__ == '__main__':
    main()




