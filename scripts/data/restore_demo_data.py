#!/usr/bin/env python3
"""
恢复camels_us_demo演示数据脚本
从完整的CAMELS_US数据中选择几个代表性流域创建演示数据集
"""

import os
import shutil
import sys
from pathlib import Path

# 修复Windows编码问题
try:
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.detach())
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.detach())
except:
    pass

def restore_demo_data():
    """恢复演示数据集"""
    
    print("🔄 正在恢复 camels_us_demo 演示数据...")
    
    # 定义路径
    source_dir = Path("data/CAMELS_US")
    demo_dir = Path("data/camels_us_demo")
    
    # 选择4个代表性流域作为演示数据
    # 这些流域来自不同地区，具有代表性
    demo_basins = [
        "01022500",  # 东北部流域
        "01547700",  # 东北部流域
        "02064000",  # 东南部流域  
        "03015500"   # 东南部流域
    ]
    
    print(f"📊 选择演示流域: {', '.join(demo_basins)}")
    
    # 创建演示数据目录结构
    demo_dir.mkdir(exist_ok=True)
    
    # 1. 复制流域属性文件
    print("📋 复制流域属性文件...")
    attr_files = [
        "camels_clim.txt",
        "camels_geol.txt", 
        "camels_hydro.txt",
        "camels_name.txt",
        "camels_soil.txt",
        "camels_topo.txt",
        "camels_vege.txt"
    ]
    
    for attr_file in attr_files:
        src = source_dir / attr_file
        dst = demo_dir / attr_file
        if src.exists():
            shutil.copy2(src, dst)
            print(f"  ✅ 复制: {attr_file}")
        else:
            print(f"  ❌ 缺失: {attr_file}")
    
    # 2. 复制camels_attributes_v2.0目录
    print("📁 复制属性目录...")
    src_attr_dir = source_dir / "camels_attributes_v2.0"
    dst_attr_dir = demo_dir / "camels_attributes_v2.0"
    
    if src_attr_dir.exists():
        if dst_attr_dir.exists():
            shutil.rmtree(dst_attr_dir)
        shutil.copytree(src_attr_dir, dst_attr_dir)
        print("  ✅ 复制: camels_attributes_v2.0/")
    else:
        print("  ❌ 缺失: camels_attributes_v2.0/")
    
    # 3. 创建演示数据的basin_mean_forcing目录
    print("🌤️ 创建气象数据目录...")
    demo_forcing_dir = demo_dir / "basin_mean_forcing"
    demo_forcing_dir.mkdir(exist_ok=True)
    
    # 复制daymet数据
    src_daymet = source_dir / "basin_mean_forcing" / "daymet"
    dst_daymet = demo_forcing_dir / "daymet"
    
    if src_daymet.exists():
        dst_daymet.mkdir(exist_ok=True)
        
        # 复制每个流域的daymet数据
        for basin in demo_basins:
            # 查找流域数据文件
            basin_files = list(src_daymet.glob(f"**/{basin}_*.txt"))
            if basin_files:
                for file in basin_files:
                    # 保持目录结构
                    rel_path = file.relative_to(src_daymet)
                    dst_file = dst_daymet / rel_path
                    dst_file.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(file, dst_file)
                print(f"  ✅ 复制流域 {basin} 的daymet数据")
            else:
                print(f"  ⚠️ 未找到流域 {basin} 的daymet数据")
        
        print("  ✅ 复制: daymet/")
    else:
        print("  ❌ 缺失: daymet/")
    
    # 复制maurer数据
    src_maurer = source_dir / "basin_mean_forcing" / "maurer"
    dst_maurer = demo_forcing_dir / "maurer"
    
    if src_maurer.exists():
        dst_maurer.mkdir(exist_ok=True)
        
        # 复制每个流域的maurer数据
        for basin in demo_basins:
            basin_files = list(src_maurer.glob(f"**/{basin}_*.txt"))
            if basin_files:
                for file in basin_files:
                    rel_path = file.relative_to(src_maurer)
                    dst_file = dst_maurer / rel_path
                    dst_file.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(file, dst_file)
                print(f"  ✅ 复制流域 {basin} 的maurer数据")
        
        print("  ✅ 复制: maurer/")
    else:
        print("  ❌ 缺失: maurer/")
    
    # 复制nldas数据
    src_nldas = source_dir / "basin_mean_forcing" / "nldas"
    dst_nldas = demo_forcing_dir / "nldas"
    
    if src_nldas.exists():
        dst_nldas.mkdir(exist_ok=True)
        
        # 复制每个流域的nldas数据
        for basin in demo_basins:
            basin_files = list(src_nldas.glob(f"**/{basin}_*.txt"))
            if basin_files:
                for file in basin_files:
                    rel_path = file.relative_to(src_nldas)
                    dst_file = dst_nldas / rel_path
                    dst_file.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(file, dst_file)
                print(f"  ✅ 复制流域 {basin} 的nldas数据")
        
        print("  ✅ 复制: nldas/")
    else:
        print("  ❌ 缺失: nldas/")
    
    # 4. 创建演示数据的usgs_streamflow目录
    print("🌊 创建径流数据目录...")
    demo_streamflow_dir = demo_dir / "usgs_streamflow"
    demo_streamflow_dir.mkdir(exist_ok=True)
    
    src_streamflow = source_dir / "usgs_streamflow"
    if src_streamflow.exists():
        # 复制每个流域的径流数据
        for basin in demo_basins:
            # 查找流域径流文件
            basin_files = list(src_streamflow.glob(f"**/{basin}_*.txt"))
            if basin_files:
                for file in basin_files:
                    # 保持目录结构
                    rel_path = file.relative_to(src_streamflow)
                    dst_file = demo_streamflow_dir / rel_path
                    dst_file.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(file, dst_file)
                print(f"  ✅ 复制流域 {basin} 的径流数据")
            else:
                print(f"  ⚠️ 未找到流域 {basin} 的径流数据")
        
        print("  ✅ 复制: usgs_streamflow/")
    else:
        print("  ❌ 缺失: usgs_streamflow/")
    
    # 5. 创建hourly目录（如果存在）
    print("⏰ 创建小时数据目录...")
    src_hourly = source_dir / "hourly"
    dst_hourly = demo_dir / "hourly"
    
    if src_hourly.exists():
        if dst_hourly.exists():
            shutil.rmtree(dst_hourly)
        shutil.copytree(src_hourly, dst_hourly)
        print("  ✅ 复制: hourly/")
    else:
        print("  ⚠️ 小时数据目录不存在，跳过")
    
    # 6. 创建README文件
    print("📝 创建说明文件...")
    readme_content = f"""# CAMELS-US 演示数据集

## 概述
这是一个轻量级的CAMELS-US演示数据集，包含4个代表性流域的完整数据。

## 包含的流域
{chr(10).join([f"- {basin}" for basin in demo_basins])}

## 数据内容
- 流域属性数据 (camels_attributes_v2.0/)
- 气象强迫数据 (basin_mean_forcing/)
  - daymet: Daymet气象数据
  - maurer: Maurer气象数据  
  - nldas: NLDAS气象数据
- 径流观测数据 (usgs_streamflow/)
- 小时数据 (hourly/, 如果可用)

## 使用方法
此数据集可用于：
1. 快速验证neuralhydrology库的安装
2. 演示和测试功能
3. 开发新的模型和算法

## 注意事项
- 这是演示数据集，仅包含4个流域
- 用于完整训练请使用 data/CAMELS_US/ 目录
- 数据格式与完整数据集完全兼容
"""
    
    readme_file = demo_dir / "readme.txt"
    with open(readme_file, 'w', encoding='utf-8') as f:
        f.write(readme_content)
    print("  ✅ 创建: readme.txt")
    
    print(f"\n🎉 演示数据恢复完成！")
    print(f"📁 演示数据目录: {demo_dir}")
    print(f"📊 包含流域: {', '.join(demo_basins)}")
    print(f"💾 数据大小: 约 {get_dir_size(demo_dir):.1f} MB")

def get_dir_size(path):
    """计算目录大小（MB）"""
    total_size = 0
    for dirpath, dirnames, filenames in os.walk(path):
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            if os.path.exists(filepath):
                total_size += os.path.getsize(filepath)
    return total_size / (1024 * 1024)  # 转换为MB

if __name__ == "__main__":
    restore_demo_data()
