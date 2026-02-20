#!/usr/bin/env python3
"""
GEE数据转换为NeuralHydrology格式
将GEE导出的CSV文件转换为NeuralHydrology可以直接使用的数据格式
"""

import pandas as pd
import numpy as np
from pathlib import Path
import shutil
import sys

if sys.platform.startswith("win"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

def convert_gee_to_neuralhydrology(gee_data_dir, output_dir, basin_id):
    """
    将GEE导出的数据转换为NeuralHydrology格式
    
    Parameters
    ----------
    gee_data_dir : str
        GEE导出数据的目录
    output_dir : str
        输出目录
    basin_id : str
        流域ID
    """
    
    print(f"🔄 转换GEE数据为NeuralHydrology格式")
    print(f"输入目录: {gee_data_dir}")
    print(f"输出目录: {output_dir}")
    print(f"流域ID: {basin_id}")
    
    # 创建输出目录结构
    output_path = Path(output_dir)
    time_series_dir = output_path / "time_series"
    attributes_dir = output_path / "attributes"
    basin_boundaries_dir = output_path / "basin_boundaries"
    
    time_series_dir.mkdir(parents=True, exist_ok=True)
    attributes_dir.mkdir(parents=True, exist_ok=True)
    basin_boundaries_dir.mkdir(parents=True, exist_ok=True)
    
    # 1. 处理时间序列数据
    print("\n📊 处理时间序列数据...")
    
    # 读取气象数据
    meteo_file = Path(gee_data_dir) / f"{basin_id}_lump_camels_forcing.csv"
    if meteo_file.exists():
        df_meteo = pd.read_csv(meteo_file)
        print(f"✅ 读取气象数据: {len(df_meteo)} 行")
        
        # 转换为CAMELS格式
        df_camels = df_meteo.copy()
        
        # 确保列名正确
        column_mapping = {
            'Year': 'Year',
            'Mnth': 'Mnth', 
            'Day': 'Day',
            'prcp(mm/day)': 'prcp(mm/day)',
            'tmean(C)': 'tmean(C)',
            'tmin(C)': 'tmin(C)',
            'tmax(C)': 'tmax(C)',
            'srad(W/m2)': 'srad(W/m2)',
            'vp(Pa)': 'vp(Pa)'
        }
        
        df_camels = df_camels.rename(columns=column_mapping)
        
        # 重新排列列
        date_cols = ['Year', 'Mnth', 'Day']
        other_cols = [col for col in df_camels.columns if col not in date_cols]
        df_camels = df_camels[date_cols + other_cols]
        
        # 保存为CAMELS格式
        camels_file = time_series_dir / f"{basin_id}_lump_camels_forcing.txt"
        df_camels.to_csv(camels_file, sep='\t', index=False, float_format='%.6f')
        print(f"✅ 保存CAMELS格式文件: {camels_file}")
        
    else:
        print(f"❌ 气象数据文件不存在: {meteo_file}")
        return False
    
    # 2. 处理径流数据
    print("\n💧 处理径流数据...")
    
    streamflow_file = Path(gee_data_dir) / f"{basin_id}_streamflow.csv"
    if streamflow_file.exists():
        df_streamflow = pd.read_csv(streamflow_file)
        print(f"✅ 读取径流数据: {len(df_streamflow)} 行")
        
        # 转换为CAMELS格式
        df_q = df_streamflow.copy()
        
        # 添加径流列
        df_q['QObs(mm/d)'] = df_q['total_precipitation']  # 使用模拟径流
        
        # 重新排列列
        date_cols = ['Year', 'Mnth', 'Day']
        q_cols = ['QObs(mm/d)']
        df_q = df_q[date_cols + q_cols]
        
        # 保存径流文件
        q_file = time_series_dir / f"{basin_id}_streamflow_qc.txt"
        df_q.to_csv(q_file, sep='\t', index=False, float_format='%.6f')
        print(f"✅ 保存径流文件: {q_file}")
        
    else:
        print(f"❌ 径流数据文件不存在: {streamflow_file}")
        return False
    
    # 3. 处理流域属性
    print("\n🏔️ 处理流域属性...")
    
    attributes_file = Path(gee_data_dir) / f"{basin_id}_basin_attributes.csv"
    if attributes_file.exists():
        df_attrs = pd.read_csv(attributes_file)
        print(f"✅ 读取流域属性: {len(df_attrs)} 行")
        
        # 转换为CAMELS属性格式
        df_camels_attrs = pd.DataFrame({
            'basin_id': [basin_id],
            'area_km2': [df_attrs['area_km2'].iloc[0]],
            'centroid_lon': [df_attrs['centroid_lon'].iloc[0]],
            'centroid_lat': [df_attrs['centroid_lat'].iloc[0]],
            'elevation_min': [df_attrs['elevation_min'].iloc[0]],
            'elevation_max': [df_attrs['elevation_max'].iloc[0]],
            'elevation_mean': [df_attrs['elevation_mean'].iloc[0]],
            'slope_mean': [df_attrs['slope_mean'].iloc[0]],
            'landcover_forest': [df_attrs['landcover_forest'].iloc[0] if 'landcover_forest' in df_attrs.columns else 0],
            'landcover_grassland': [df_attrs['landcover_grassland'].iloc[0] if 'landcover_grassland' in df_attrs.columns else 0],
            'landcover_cropland': [df_attrs['landcover_cropland'].iloc[0] if 'landcover_cropland' in df_attrs.columns else 0]
        })
        
        # 保存属性文件
        attrs_file = attributes_dir / f"{basin_id}_attributes.csv"
        df_camels_attrs.to_csv(attrs_file, index=False)
        print(f"✅ 保存属性文件: {attrs_file}")
        
    else:
        print(f"❌ 流域属性文件不存在: {attributes_file}")
        return False
    
    # 4. 创建流域文件
    print("\n📋 创建流域文件...")
    
    basin_file = output_path / f"{basin_id}.txt"
    with open(basin_file, 'w') as f:
        f.write(basin_id)
    print(f"✅ 创建流域文件: {basin_file}")
    
    # 5. 创建NeuralHydrology配置文件
    print("\n⚙️ 创建NeuralHydrology配置文件...")
    
    config_content = f"""# NeuralHydrology配置文件 - 海河流域
# 自动生成于: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}

# 实验配置
experiment_name: {basin_id}_neuralhydrology
dataset: generic

# 数据目录
data_dir: {output_path.absolute()}

# 流域文件
train_basin_file: {basin_file.absolute()}
validation_basin_file: {basin_file.absolute()}
test_basin_file: {basin_file.absolute()}

# 时间范围
train_start_date: 01/01/2020
train_end_date: 31/12/2020
validation_start_date: 01/01/2019
validation_end_date: 31/12/2019
test_start_date: 01/01/2021
test_end_date: 31/12/2021

# 模型配置
model: cudalstm
head: regression
hidden_size: 128
initial_forget_bias: 3
output_dropout: 0.4
output_activation: linear

# 训练配置
epochs: 50
batch_size: 256
optimizer: Adam
loss: MSE

# 学习率调度
learning_rate:
  0: 0.001
  20: 0.0005
  40: 0.0001

# 数据配置
forcings:
  - camels

dynamic_inputs:
  - prcp(mm/day)
  - tmean(C)
  - tmin(C)
  - tmax(C)
  - srad(W/m2)
  - vp(Pa)

# 目标变量
target_variables:
  - QObs(mm/d)

# 数据预处理
clip_targets_to_zero:
  - QObs(mm/d)

# 训练参数
seq_length: 365
predict_last_n: 1
num_workers: 8
validate_every: 5
validate_n_random_basins: 1

# 正则化
clip_gradient_norm: 1.0

# 日志和保存
log_interval: 10
log_tensorboard: true
log_n_figures: 1
save_weights_every: 10

# 评估指标
metrics:
  - NSE
  - KGE
  - Alpha-NSE

# 随机种子
seed: 42

# 设备配置
device: cuda:0
"""
    
    config_file = output_path / f"{basin_id}_config.yml"
    with open(config_file, 'w', encoding='utf-8') as f:
        f.write(config_content)
    print(f"✅ 创建配置文件: {config_file}")
    
    # 6. 创建使用说明
    print("\n📖 创建使用说明...")
    
    readme_content = f"""# NeuralHydrology海河流域数据

## 📁 目录结构
```
{output_path.name}/
├── time_series/
│   ├── {basin_id}_lump_camels_forcing.txt  # 气象数据
│   └── {basin_id}_streamflow_qc.txt        # 径流数据
├── attributes/
│   └── {basin_id}_attributes.csv           # 流域属性
├── basin_boundaries/                       # 流域边界 (可选)
├── {basin_id}.txt                          # 流域ID文件
├── {basin_id}_config.yml                   # NeuralHydrology配置
└── README.md                               # 本文件
```

## 🚀 使用方法

### 1. 直接训练
```bash
python neuralhydrology/nh_run.py train --config-file {basin_id}_config.yml --gpu 0
```

### 2. 评估模型
```bash
python neuralhydrology/nh_run.py evaluate --run-dir runs/{basin_id}_neuralhydrology_*/ --period test
```

## 📊 数据说明

### 气象数据
- **prcp(mm/day)**: 日降水
- **tmean(C)**: 日平均温度
- **tmin(C)**: 日最低温度
- **tmax(C)**: 日最高温度
- **srad(W/m2)**: 日太阳辐射
- **vp(Pa)**: 日水汽压

### 径流数据
- **QObs(mm/d)**: 日径流 (模拟数据)

### 流域属性
- **area_km2**: 流域面积
- **elevation_***: 高程统计
- **slope_mean**: 平均坡度
- **landcover_***: 土地利用类型

## ⚠️ 注意事项

1. **径流数据**: 当前使用模拟数据，实际应用中需要真实观测数据
2. **数据质量**: 请验证数据的时空连续性和合理性
3. **模型参数**: 可根据实际情况调整模型参数

## 🔧 自定义配置

修改 `{basin_id}_config.yml` 文件中的参数：
- 调整训练轮数、批次大小
- 修改模型架构参数
- 设置不同的时间分割
- 添加更多评估指标

## 📈 预期结果

使用此配置训练后，预期能够：
- 学习流域的水文响应模式
- 预测日径流变化
- 评估模型性能指标 (NSE, KGE等)

生成时间: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}
"""
    
    readme_file = output_path / "README.md"
    with open(readme_file, 'w', encoding='utf-8') as f:
        f.write(readme_content)
    print(f"✅ 创建使用说明: {readme_file}")
    
    print(f"\n🎉 转换完成!")
    print(f"📁 输出目录: {output_path}")
    print(f"📄 主要文件:")
    print(f"  - {camels_file.name} (气象数据)")
    print(f"  - {q_file.name} (径流数据)")
    print(f"  - {attrs_file.name} (流域属性)")
    print(f"  - {config_file.name} (配置文件)")
    print(f"  - {readme_file.name} (使用说明)")
    
    return True

def main():
    """主函数"""
    print("🔄 GEE数据转换为NeuralHydrology格式")
    print("=" * 50)
    
    # 设置路径
    gee_data_dir = "NeuralHydrology_Data"  # GEE导出数据目录
    output_dir = "data/haihe/neuralhydrology"  # 输出目录
    basin_id = "haihe_basin"
    
    # 检查输入目录
    if not Path(gee_data_dir).exists():
        print(f"❌ GEE数据目录不存在: {gee_data_dir}")
        print("💡 请先运行GEE代码导出数据")
        return
    
    # 执行转换
    success = convert_gee_to_neuralhydrology(gee_data_dir, output_dir, basin_id)
    
    if success:
        print(f"\n✅ 转换成功!")
        print(f"🚀 现在可以使用以下命令开始训练:")
        print(f"python neuralhydrology/nh_run.py train --config-file {output_dir}/haihe_basin_config.yml --gpu 0")
    else:
        print(f"\n❌ 转换失败!")

if __name__ == "__main__":
    main()
