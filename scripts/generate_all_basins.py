#!/usr/bin/env python3
"""
生成所有流域ID列表的脚本
"""
import os
import glob

def generate_all_basins():
    """从CAMELS_US数据目录中提取所有流域ID"""
    data_dir = "data/CAMELS_US/usgs_streamflow"
    basin_files = glob.glob(os.path.join(data_dir, "*", "*.txt"))
    
    basin_ids = []
    for file_path in basin_files:
        # 从文件名中提取流域ID
        filename = os.path.basename(file_path)
        basin_id = filename.split('_')[0]
        basin_ids.append(basin_id)
    
    # 去重并排序
    basin_ids = sorted(list(set(basin_ids)))
    
    print(f"找到 {len(basin_ids)} 个流域")
    
    # 保存到文件
    with open("examples/01-Introduction/all_basins.txt", "w") as f:
        for basin_id in basin_ids:
            f.write(f"{basin_id}\n")
    
    print(f"流域ID已保存到 examples/01-Introduction/all_basins.txt")
    return basin_ids

if __name__ == "__main__":
    generate_all_basins()
