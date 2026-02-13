#!/usr/bin/env python3
"""
脚本3: 使用 Earth Engine 为海河小流域批量导出 ERA5-Land 气象数据（CSV �?Google Drive�?
注意�?1) 你需要已完成 `earthengine authenticate` 认证�?2) 本脚本将分批（每�?~100 个流域）+ 分时段（默认�?5 年）创建多个导出任务，避免单任务过大�?3) 数据源支持两种模式：
   - 日聚合：`ECMWF/ERA5_LAND/DAILY_AGGR`
   - 逐小时：`ECMWF/ERA5_LAND/HOURLY`（便于后续聚合为 CAMELS 变量�?
用法示例�?  conda run -n neuralhydrology_gpu python src/haihe_river/scripts/03_ee_export_era5l.py \
    --basins-dir data/haihe/basins_individual \
    --drive-folder Caravan_Haihe_ERA5L \
    --start 1981-01-01 --end 2020-12-31 \
    --group-size 100 --years-per-chunk 5

导出结果�?  Google Drive/<Caravan_Haihe_ERA5L>/
    - era5l_daily_Gxxx_Txx_YYYY_YYYY.csv�?-mode daily�?    - era5l_hourly_Gxxx_Txx_YYYY_YYYY.csv�?-mode hourly�?"""

import os
import sys
import argparse
from datetime import datetime
from pathlib import Path
from typing import List, Tuple

import ee  # earthengine-api

from neuralhydrology.utils.era5l_export import ExportConfig, get_export_config


def list_geojson_files(basins_dir: Path) -> List[Path]:
    files = sorted(basins_dir.glob('*.geojson'))
    if not files:
        raise FileNotFoundError(f"No *.geojson basin files found in {basins_dir}")
    return files


def build_feature_collection(files: List[Path]) -> ee.FeatureCollection:
    """Build an ee.FeatureCollection from local GeoJSON files."""
    import json
    features = []
    for f in files:
        try:
            with open(f, 'r', encoding='utf-8') as fp:
                obj = json.load(fp)
            # 兼容 Feature/FeatureCollection
            if obj.get('type') == 'FeatureCollection':
                feats = obj.get('features', [])
                if not feats:
                    continue
                feat0 = feats[0]
                geom = feat0.get('geometry')
                props = feat0.get('properties', {}) or {}
            elif obj.get('type') == 'Feature':
                geom = obj.get('geometry')
                props = obj.get('properties', {}) or {}
            else:
                # 可能�?bare geometry
                geom = obj
                props = {}
            if not geom:
                continue
            basin_id = props.get('basin_id', f.stem)
            ee_feat = ee.Feature(ee.Geometry(geom), {'basin_id': str(basin_id)})
            features.append(ee_feat)
        except Exception:
            continue
    if not features:
        raise RuntimeError("无法从输入文件构建任�?Feature")
    return ee.FeatureCollection(features)


def split_list(a: List, size: int) -> List[List]:
    return [a[i:i + size] for i in range(0, len(a), size)]


def year_chunks(start_date: str, end_date: str, years_per_chunk: int) -> List[Tuple[str, str]]:
    s = datetime.strptime(start_date, '%Y-%m-%d').year
    e = datetime.strptime(end_date, '%Y-%m-%d').year
    chunks = []
    y = s
    while y <= e:
        y2 = min(y + years_per_chunk - 1, e)
        chunks.append((f"{y}-01-01", f"{y2}-12-31"))
        y = y2 + 1
    return chunks


def export_chunk(fc: ee.FeatureCollection, start: str, end: str, drive_folder: str, config: ExportConfig,
                 desc_prefix: str, file_prefix: str, scale: int = 10000) -> ee.batch.Task:
    """Create a CSV export task for one feature group and one time chunk."""
    col = (ee.ImageCollection(config.dataset_id)
           .filterDate(start, end)
           .select(config.bands))

    def per_image(image):
        image = ee.Image(image)
        # Add a date key for downstream processing.
        date_str = image.date().format(config.date_format)
        fc_stats = image.reduceRegions(
            collection=fc,
            reducer=ee.Reducer.mean(),
            scale=scale
        ).map(lambda f: f.set({'system_index': date_str}))
        return fc_stats

    fc_all = col.map(per_image).flatten()

    task_desc = f"{desc_prefix}_{start[:4]}_{end[:4]}"
    task = ee.batch.Export.table.toDrive(
        collection=fc_all,
        description=task_desc,
        folder=drive_folder,
        fileNamePrefix=file_prefix,
        fileFormat='CSV'
    )
    task.start()
    return task


def validate_bands(config: ExportConfig):
    """Validate that required bands exist in the selected image collection."""
    sample = ee.ImageCollection(config.dataset_id).first()
    if sample is None:
        raise SystemExit(f"Failed to get a sample image from dataset {config.dataset_id}; check dataset ID/time range.")
    available = set(sample.bandNames().getInfo())
    missing = sorted(set(config.bands) - available)
    if missing:
        raise SystemExit(
            f"以下 band 在数据集 {config.dataset_id} 中不存在：{missing}\n"
            "Please adjust --mode or custom configuration to match available bands."
        )


def main():
    parser = argparse.ArgumentParser(description="Batch export ERA5-Land meteorological data to CSV files in Google Drive")
    parser.add_argument('--basins-dir', default='data/haihe/basins_individual', help='小流�?GeoJSON 目录')
    parser.add_argument('--drive-folder', required=True, help='Google Drive 目标文件夹名')
    parser.add_argument('--start', default='1981-01-01', help='开始日�?YYYY-MM-DD')
    parser.add_argument('--end', default='2020-12-31', help='结束日期 YYYY-MM-DD')
    parser.add_argument('--group-size', type=int, default=100, help='每批流域数量')
    parser.add_argument('--years-per-chunk', type=int, default=5, help='每个时间片的年数')
    parser.add_argument('--scale', type=int, default=10000, help='reduceRegions spatial resolution in meters')
    parser.add_argument('--mode', choices=['daily', 'hourly'], default='daily',
                        help='Export mode: daily uses DAILY_AGGR, hourly uses HOURLY')
    args = parser.parse_args()

    # 初始�?EE
    ee.Initialize()

    config = get_export_config(args.mode)
    validate_bands(config)

    basins_dir = Path(args.basins_dir)
    files = list_geojson_files(basins_dir)
    print(f"发现小流域文件数: {len(files)}")

    groups = split_list(files, args.group_size)
    time_windows = year_chunks(args.start, args.end, args.years_per_chunk)

    all_tasks = []
    for gi, group_files in enumerate(groups, start=1):
        print(f"构建�?{gi}/{len(groups)} �?FeatureCollection，大�? {len(group_files)}")
        fc = build_feature_collection(group_files)
        for ti, (s, e) in enumerate(time_windows, start=1):
            desc_prefix = f"{config.file_prefix.upper()}_G{gi:03d}_T{ti:02d}"
            file_prefix = f"{config.file_prefix}_G{gi:03d}_T{ti:02d}_{s[:4]}_{e[:4]}"
            task = export_chunk(fc, s, e, args.drive_folder, config, desc_prefix, file_prefix, args.scale)
            all_tasks.append(task)
            print(f"已启动任�? {desc_prefix} {s}–{e}")

    print("总任务数:", len(all_tasks))
    print("Tip: check task status in Earth Engine Tasks panel or with the earthengine CLI.")


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print('[ERROR]', e)
        sys.exit(1)


