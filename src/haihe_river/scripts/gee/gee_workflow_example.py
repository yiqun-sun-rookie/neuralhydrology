#!/usr/bin/env python3
"""
GEE混合工作流程示例
演示预览 + 自动化的完整流程
"""

from pathlib import Path
import sys
from pathlib import Path as _Path

if sys.platform.startswith("win"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

# Ensure local imports work when executed as a script
_SCRIPT_DIR = _Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from gee_hybrid_workflow import GEEHybridWorkflow

def example_workflow():
    """示例工作流程"""
    print("🌍 GEE混合工作流程示例")
    print("=" * 50)
    
    # 1. 初始化工作流程
    workflow = GEEHybridWorkflow()
    
    # 2. 定义流域信息
    basin_info = {
        # Placeholder path: replace with your own basin boundary shapefile.
        'shapefile': 'data/haihe_river_example/basin_boundary.shp',
        'basin_id': 'example_basin',
        'start_date': '2020-01-01',
        'end_date': '2020-12-31'
    }
    
    print("📋 流域信息:")
    for key, value in basin_info.items():
        print(f"  {key}: {value}")
    
    # 3. 生成预览代码
    print(f"\n🔍 步骤1: 生成GEE预览代码")
    preview_file = workflow.generate_gee_preview_code(
        basin_info['shapefile'],
        basin_info['start_date'],
        basin_info['end_date'],
        output_format="html"  # 生成HTML预览页面
    )
    
    print(f"✅ 预览代码已生成: {preview_file}")
    print("💡 请打开HTML文件，复制JavaScript代码到GEE Code Editor运行")
    
    # 4. 等待用户确认
    print(f"\n⏳ 步骤2: 等待预览确认")
    print("请在GEE Code Editor中:")
    print("  1. 检查流域边界显示")
    print("  2. 验证数据时间范围")
    print("  3. 确认变量值合理")
    print("  4. 检查无大量缺失值")
    
    response = input("\n预览确认无误? (y/n): ").lower().strip()
    
    if response == 'y':
        # 5. 自动化数据提取
        print(f"\n🚀 步骤3: 自动化数据提取")
        output_file = workflow.automated_extraction(
            basin_info['shapefile'],
            basin_info['start_date'],
            basin_info['end_date'],
            basin_info['basin_id'],
            confirm_preview=False  # 已经确认过了
        )
        
        if output_file:
            print(f"🎉 工作流程完成!")
            print(f"📄 输出文件: {output_file}")
            
            # 6. 显示数据统计
            import pandas as pd
            df = pd.read_csv(output_file, sep='\t')
            print(f"\n📊 数据统计:")
            print(f"  数据天数: {len(df)}")
            print(f"  变量数量: {len(df.columns) - 3}")  # 减去Year, Mnth, Day
            print(f"  时间范围: {df['Year'].min()}-{df['Year'].max()}")
    else:
        print("❌ 请先完成数据预览和确认")

def batch_example():
    """批量处理示例"""
    print("\n🔄 批量处理示例")
    print("=" * 30)
    
    workflow = GEEHybridWorkflow()
    
    # 定义多个流域
    basin_list = [
        {'id': 'basin_001', 'shapefile': 'data/basins/basin_001.shp'},
        {'id': 'basin_002', 'shapefile': 'data/basins/basin_002.shp'},
        {'id': 'basin_003', 'shapefile': 'data/basins/basin_003.shp'},
    ]
    
    print(f"📋 批量处理 {len(basin_list)} 个流域:")
    for basin in basin_list:
        print(f"  - {basin['id']}: {basin['shapefile']}")
    
    # 批量处理
    results = workflow.batch_processing(
        basin_list,
        start_date='2020-01-01',
        end_date='2020-12-31',
        output_dir='data/gee_batch_output',
        skip_preview=False  # 先预览第一个流域
    )
    
    print(f"\n📊 批量处理结果:")
    for result in results:
        status = "✅" if result['status'] == 'success' else "❌"
        print(f"  {status} {result['basin_id']}: {result['status']}")

if __name__ == "__main__":
    # 运行单个流域示例
    example_workflow()
    
    # 运行批量处理示例 (可选)
    # batch_example()

