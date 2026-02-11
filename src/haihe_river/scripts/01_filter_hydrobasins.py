#!/usr/bin/env python3
import os
import sys
from pathlib import Path

# Fix PROJ data path on Windows/conda if missing
if 'PROJ_LIB' not in os.environ:
    exe = Path(sys.executable)
    cand = exe.parent / 'Library' / 'share' / 'proj'
    if cand.exists():
        os.environ['PROJ_LIB'] = str(cand)
        os.environ.setdefault('GEOPANDAS_IO_ENGINE', 'fiona')
"""脚本1: �?HydroBASINS 筛选海河流域内的小流域

功能�?
1. 读取海河大流域边�?shp
2. 读取 HydroBASINS 数据
3. 筛选出落在海河流域内的小流�?
4. 生成筛选后的小流域集合文件

使用方法�?
    python projects/haihe/scripts/01_filter_hydrobasins.py \
        --haihe-shp data/haihe/boundary/haihe_basin.shp \
        --hydrobasins-shp <你的HydroBASINS文件路径> \
        --output-dir data/haihe/hydrobasins/lev12

参数说明�?
    --haihe-shp: 海河大流域边界文件路�?
    --hydrobasins-shp: HydroBASINS 数据文件路径（如 hybas_as_lev12_v1c.shp�?
    --output-dir: 输出目录
    --overlap-ratio: 最小重叠比例阈值（默认0.05，即5%�?
"""

import os
import sys
import argparse
import geopandas as gpd
from shapely.ops import unary_union
from pathlib import Path
from tqdm import tqdm


def to_epsg4326(gdf: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    """Convert to EPSG:4326 CRS."""
    if gdf.crs is None:
        raise ValueError("[ERROR] Input data has no CRS; set the correct CRS for the shapefile.")
    if gdf.crs.to_string() != "EPSG:4326":
        print(f"[INFO] Reproject from {gdf.crs} to EPSG:4326")
        gdf = gdf.to_crs(epsg=4326)
    return gdf


def filter_basins(haihe_shp: str, hydrobasins_shp: str, output_dir: str, 
                  overlap_ratio_min: float = 0.05):
    """筛选海河流域内的小流域"""
    
    # 创建输出目录
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    output_gpkg = output_dir / "haihe_hydrobasins_lev12.gpkg"
    output_csv = output_dir / "haihe_hydrobasins_lev12_list.csv"
    
    print("=" * 60)
    print("HydroBASINS sub-basin filtering")
    print("=" * 60)
    
    # 1. 读取海河边界
    print(f"\n[Step 1/4] Read Haihe basin boundary...")
    print(f"  文件: {haihe_shp}")
    if not os.path.exists(haihe_shp):
        raise FileNotFoundError(f"[ERROR] Haihe boundary file not found: {haihe_shp}")
    
    haihe = gpd.read_file(haihe_shp)
    haihe = to_epsg4326(haihe)
    print(f"  [OK] Loaded {len(haihe)} features")
    
    # 合并所有海河边界要�?
    haihe_union = unary_union(haihe.geometry.values)
    print("  [OK] Merged to a single geometry")
    
    # 2. 读取 HydroBASINS 数据
    print(f"\n[步骤2/4] 读取 HydroBASINS 数据...")
    print(f"  文件: {hydrobasins_shp}")
    if not os.path.exists(hydrobasins_shp):
        raise FileNotFoundError(f"[ERROR] HydroBASINS file not found: {hydrobasins_shp}")
    
    hybas = gpd.read_file(hydrobasins_shp)
    hybas = to_epsg4326(hybas)
    print(f"  [OK] 已读取，�?{len(hybas)} 个小流域")
    
    # 检查必要字�?
    if "HYBAS_ID" not in hybas.columns:
        raise ValueError("[ERROR] HydroBASINS data missing HYBAS_ID field.")
    
    # 清理无效几何
    hybas = hybas[~hybas.geometry.is_empty & hybas.geometry.notna()].copy()
    print(f"  [OK] Valid basin count after cleanup: {len(hybas)}")
    
    # 3. 空间筛�?
    print(f"\n[Step 3/4] Spatial filtering (min overlap {overlap_ratio_min*100:.1f}%)...")
    candidates = []
    
    for idx in tqdm(range(len(hybas)), desc="  Filtering"):
        geom = hybas.geometry.iloc[idx]
        if geom is None or geom.is_empty:
            continue
        
        # 检查是否与海河边界相交
        if not geom.intersects(haihe_union):
            continue
        
        # 计算相交面积比例
        try:
            inter = geom.intersection(haihe_union)
            if inter.is_empty:
                continue
            
            # 计算重叠比例
            ratio = inter.area / geom.area if geom.area > 0 else 0.0
            if ratio >= overlap_ratio_min:
                candidates.append(idx)
        except Exception as e:
            # 几何操作失败时跳�?
            continue
    
    if not candidates:
        print(f"\n[WARNING] 未找到符合条件的小流域！")
        print("  Suggestion: lower --overlap-ratio and retry.")
        return False
    
    # 4. 生成结果
    print(f"\n[步骤4/4] 生成结果文件...")
    sub = hybas.iloc[candidates].copy()
    
    # 生成 basin_id（使�?HydroBASINS ID�?
    if "HYBAS_ID" in sub.columns:
        sub["basin_id"] = sub["HYBAS_ID"].apply(lambda v: f"HB{int(v)}")
    else:
        sub["basin_id"] = [f"HB{i:06d}" for i in range(len(sub))]
    
    # 保存 GeoPackage
    if output_gpkg.exists():
        print(f"  [INFO] 删除已存在的文件: {output_gpkg}")
        os.remove(output_gpkg)
    
    sub.to_file(str(output_gpkg), layer="basins", driver="GPKG")
    print(f"  [OK] 已保存集合文�? {output_gpkg}")
    
    # 保存列表 CSV
    cols_to_save = ["basin_id", "HYBAS_ID"]
    optional_cols = ["SUB_AREA", "NEXT_DOWN", "MAIN_BAS", "COAST"]
    for col in optional_cols:
        if col in sub.columns:
            cols_to_save.append(col)
    
    sub[cols_to_save].to_csv(output_csv, index=False, encoding="utf-8-sig")
    print(f"  [OK] 已保存列表文�? {output_csv}")
    
    # 统计信息
    print("\n" + "=" * 60)
    print("筛选完成！")
    print("=" * 60)
    print(f"筛选出的小流域数量: {len(sub)}")
    print(f"输出目录: {output_dir}")
    print(f"集合文件: {output_gpkg}")
    print(f"列表文件: {output_csv}")
    
    if "SUB_AREA" in sub.columns:
        total_area = sub["SUB_AREA"].sum()
        print(f"\n统计信息:")
        print(f"  总面�? {total_area:.2f} km^2")
        print(f"  平均面积: {total_area/len(sub):.2f} km^2")
        print(f"  最大面�? {sub['SUB_AREA'].max():.2f} km^2")
        print(f"  最小面�? {sub['SUB_AREA'].min():.2f} km^2")
    
    return True


def main():
    parser = argparse.ArgumentParser(description="Filter HydroBASINS sub-basins within Haihe basin")
    parser.add_argument("--haihe-shp", 
                       default="data/haihe/boundary/haihe_basin.shp",
                       help="Haihe basin boundary shapefile path")
    parser.add_argument("--hydrobasins-shp", 
                       required=True,
                       help="HydroBASINS shapefile path (required)")
    parser.add_argument("--output-dir", 
                       default="data/haihe/hydrobasins/lev12",
                       help="Output directory (default: data/haihe/hydrobasins/lev12)")
    parser.add_argument("--overlap-ratio", 
                       type=float, 
                       default=0.05,
                       help="Minimum overlap ratio (default: 0.05, i.e. 5%%)")
    
    args = parser.parse_args()
    
    try:
        success = filter_basins(
            haihe_shp=args.haihe_shp,
            hydrobasins_shp=args.hydrobasins_shp,
            output_dir=args.output_dir,
            overlap_ratio_min=args.overlap_ratio
        )
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n[ERROR] 执行失败: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()


