#!/usr/bin/env python3
"""脚本2: 将筛选后的小流域导出为独立文�?

功能�?
1. 读取筛选后�?HydroBASINS 集合文件
2. 为每个小流域生成独立�?GeoJSON 文件
3. 生成 basin_list.txt 和文件映�?CSV

使用方法�?
    python projects/haihe/scripts/02_export_individual_basins.py \
        --input-gpkg data/haihe/hydrobasins/lev12/haihe_hydrobasins_lev12.gpkg \
        --output-dir data/haihe/basins_individual

参数说明�?
    --input-gpkg: 筛选后的集�?GeoPackage 文件
    --output-dir: 输出目录（每个小流域一个文件）
    --format: 输出格式（geojson �?shp，默�?geojson�?
"""

import os
import sys
import argparse
import geopandas as gpd
from pathlib import Path
from tqdm import tqdm
import pandas as pd


def sanitize_name(name: str) -> str:
    """清理文件名，移除非法字符"""
    # 只保留字母、数字、下划线、连字符
    cleaned = "".join(c if c.isalnum() or c in ("_", "-") else "_" for c in str(name))
    return cleaned


def export_individual_basins(input_gpkg: str, output_dir: str, file_format: str = "geojson"):
    """导出每个小流域为独立文件"""
    
    input_gpkg = Path(input_gpkg)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    list_txt = output_dir / "basin_list.txt"
    map_csv = output_dir / "basin_file_map.csv"
    
    print("=" * 60)
    print("Export individual basin files")
    print("=" * 60)
    
    # 1. 读取集合文件
    print(f"\n[步骤1/3] 读取集合文件...")
    print(f"  文件: {input_gpkg}")
    if not input_gpkg.exists():
        raise FileNotFoundError(f"[ERROR] 找不到输入文�? {input_gpkg}")
    
    # 尝试不同�?layer 名称
    layer_names = ["basins", None, "haihe_hydrobasins_lev12"]
    gdf = None
    
    for layer in layer_names:
        try:
            if layer:
                gdf = gpd.read_file(str(input_gpkg), layer=layer)
            else:
                gdf = gpd.read_file(str(input_gpkg))
            print(f"  [OK] 成功读取（layer: {layer or '默认'}），�?{len(gdf)} 个小流域")
            break
        except Exception:
            continue
    
    if gdf is None:
        raise ValueError("[ERROR] Failed to read GeoPackage file; check the file format.")
    
    # 检查必要字�?
    if "basin_id" not in gdf.columns:
        # 尝试�?HYBAS_ID 生成
        if "HYBAS_ID" in gdf.columns:
            gdf["basin_id"] = gdf["HYBAS_ID"].apply(lambda v: f"HB{int(v)}")
            print(f"  [INFO] �?HYBAS_ID 生成�?basin_id 字段")
        else:
            raise ValueError("[ERROR] 数据缺少 basin_id �?HYBAS_ID 字段")
    
    # 2. 导出每个小流�?
    print(f"\n[步骤2/3] 导出独立文件（格�? {file_format}�?..")
    records = []
    failed_count = 0
    
    # 检查输出格�?
    if file_format.lower() == "geojson":
        driver = "GeoJSON"
        ext = ".geojson"
    elif file_format.lower() in ["shp", "shapefile"]:
        driver = "ESRI Shapefile"
        ext = ".shp"
    else:
        raise ValueError(f"[ERROR] 不支持的格式: {file_format}，请使用 'geojson' �?'shp'")
    
    for idx, (_, row) in enumerate(tqdm(gdf.iterrows(), total=len(gdf), desc="  导出进度")):
        try:
            basin_id = str(row["basin_id"])
            # 清理 basin_id 作为文件�?
            clean_id = sanitize_name(basin_id)
            
            # 创建单个流域�?GeoDataFrame
            single_gdf = gpd.GeoDataFrame([row], geometry="geometry", crs=gdf.crs)
            
            # 生成文件�?
            if file_format.lower() == "geojson":
                fname = f"{clean_id}.geojson"
                fpath = output_dir / fname
                single_gdf.to_file(str(fpath), driver=driver)
            else:  # shapefile
                fname = f"{clean_id}.shp"
                fpath = output_dir / fname
                single_gdf.to_file(str(fpath), driver=driver)
            
            records.append({
                "basin_id": basin_id,
                "file_name": fname,
                "file_path": str(fpath.resolve()),
                "index": idx
            })
        except Exception as e:
            print(f"\n  [WARNING] 导出 {basin_id} 失败: {e}")
            failed_count += 1
            continue
    
    if failed_count > 0:
        print(f"\n  [WARNING] �?{failed_count} 个小流域导出失败")
    
    # 3. 生成列表文件
    print(f"\n[步骤3/3] 生成列表文件...")
    
    # basin_list.txt（NeuralHydrology 格式�?
    with open(list_txt, "w", encoding="utf-8") as f:
        for record in records:
            f.write(f"{record['basin_id']}\n")
    print(f"  [OK] 已生�?basin_list.txt: {list_txt} ({len(records)} 个流�?")
    
    # 文件映射 CSV
    df_map = pd.DataFrame(records)
    df_map.to_csv(map_csv, index=False, encoding="utf-8-sig")
    print(f"  [OK] 已生成映射文�? {map_csv}")
    
    # 统计信息
    print("\n" + "=" * 60)
    print("Export completed.")
    print("=" * 60)
    print(f"成功导出: {len(records)} 个小流域")
    print(f"输出目录: {output_dir}")
    print(f"文件格式: {file_format}")
    print(f"basin_list.txt: {list_txt}")
    print(f"文件映射: {map_csv}")
    
    return True


def main():
    parser = argparse.ArgumentParser(description="Export filtered sub-basins as individual files")
    parser.add_argument("--input-gpkg", 
                       default="data/haihe/hydrobasins/lev12/haihe_hydrobasins_lev12.gpkg",
                       help="筛选后的集�?GeoPackage 文件")
    parser.add_argument("--output-dir", 
                       default="data/haihe/basins_individual",
                       help="Output directory (default: data/haihe/basins_individual)")
    parser.add_argument("--format", 
                       choices=["geojson", "shp"],
                       default="geojson",
                       help="Output file format (default: geojson)")
    
    args = parser.parse_args()
    
    try:
        success = export_individual_basins(
            input_gpkg=args.input_gpkg,
            output_dir=args.output_dir,
            file_format=args.format
        )
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n[ERROR] 执行失败: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()


