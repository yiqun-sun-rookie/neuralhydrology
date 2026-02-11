#!/usr/bin/env python3
"""
子流域数据转换为NeuralHydrology格式
处理多个子流域数据，创建批量训练配置
"""

import pandas as pd
import numpy as np
from pathlib import Path
import shutil
import glob

def process_subwatersheds_data(gee_data_dir, output_dir, num_subwatersheds=5):
    """
    处理多个子流域数据并转换为NeuralHydrology格式
    
    Parameters
    ----------
    gee_data_dir : str
        GEE导出数据的目录
    output_dir : str
        输出目录
    num_subwatersheds : int
        子流域数量
    """
    
    print(f"🔄 处理{num_subwatersheds}个子流域数据")
    print(f"输入目录: {gee_data_dir}")
    print(f"输出目录: {output_dir}")
    
    # 创建输出目录结构
    output_path = Path(output_dir)
    time_series_dir = output_path / "time_series"
    attributes_dir = output_path / "attributes"
    
    time_series_dir.mkdir(parents=True, exist_ok=True)
    attributes_dir.mkdir(parents=True, exist_ok=True)
    
    # 处理每个子流域
    basin_ids = []
    basin_files = []
    
    for i in range(1, num_subwatersheds + 1):
        basin_id = f"haihe_sub_{i}"
        print(f"\n📊 处理子流域 {i}: {basin_id}")
        
        # 1. 处理气象数据
        meteo_file = Path(gee_data_dir) / f"{basin_id}_meteorological_data.csv"
        if meteo_file.exists():
            df_meteo = pd.read_csv(meteo_file)
            print(f"  ✅ 读取气象数据: {len(df_meteo)} 行")
            
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
            print(f"  ✅ 保存CAMELS格式文件: {camels_file}")
            
        else:
            print(f"  ❌ 气象数据文件不存在: {meteo_file}")
            continue
        
        # 2. 处理流域属性
        attrs_file = Path(gee_data_dir) / f"{basin_id}_attributes.csv"
        if attrs_file.exists():
            df_attrs = pd.read_csv(attrs_file)
            print(f"  ✅ 读取流域属性: {len(df_attrs)} 行")
            
            # 转换为CAMELS属性格式
            df_camels_attrs = pd.DataFrame({
                'basin_id': [basin_id],
                'area_km2': [df_attrs['area_km2'].iloc[0]],
                'centroid_lon': [df_attrs['centroid_lon'].iloc[0]],
                'centroid_lat': [df_attrs['centroid_lat'].iloc[0]],
                'perimeter_km': [df_attrs['perimeter_km'].iloc[0]]
            })
            
            # 保存属性文件
            attrs_output_file = attributes_dir / f"{basin_id}_attributes.csv"
            df_camels_attrs.to_csv(attrs_output_file, index=False)
            print(f"  ✅ 保存属性文件: {attrs_output_file}")
            
        else:
            print(f"  ❌ 流域属性文件不存在: {attrs_file}")
            continue
        
        # 3. 创建模拟径流数据 (实际应用中需要真实数据)
        print(f"  💧 创建模拟径流数据...")
        df_streamflow = create_simulated_streamflow(df_camels, basin_id)
        
        # 保存径流文件
        streamflow_file = time_series_dir / f"{basin_id}_streamflow_qc.txt"
        df_streamflow.to_csv(streamflow_file, sep='\t', index=False, float_format='%.6f')
        print(f"  ✅ 保存径流文件: {streamflow_file}")
        
        # 记录流域信息
        basin_ids.append(basin_id)
        basin_files.append(camels_file)
    
    # 4. 创建流域文件
    print(f"\n📋 创建流域文件...")
    
    # 训练集流域文件
    train_basins = basin_ids[:3]  # 前3个用于训练
    train_basin_file = output_path / "train_basins.txt"
    with open(train_basin_file, 'w') as f:
        for basin_id in train_basins:
            f.write(f"{basin_id}\n")
    print(f"✅ 创建训练流域文件: {train_basin_file}")
    
    # 验证集流域文件
    validation_basins = basin_ids[3:4]  # 第4个用于验证
    validation_basin_file = output_path / "validation_basins.txt"
    with open(validation_basin_file, 'w') as f:
        for basin_id in validation_basins:
            f.write(f"{basin_id}\n")
    print(f"✅ 创建验证流域文件: {validation_basin_file}")
    
    # 测试集流域文件
    test_basins = basin_ids[4:]  # 第5个用于测试
    test_basin_file = output_path / "test_basins.txt"
    with open(test_basin_file, 'w') as f:
        for basin_id in test_basins:
            f.write(f"{basin_id}\n")
    print(f"✅ 创建测试流域文件: {test_basin_file}")
    
    # 5. 创建NeuralHydrology配置文件
    print(f"\n⚙️ 创建NeuralHydrology配置文件...")
    
    config_content = f"""# NeuralHydrology配置文件 - 海河流域子流域批量训练
# 自动生成于: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}

# 实验配置
experiment_name: haihe_subwatersheds_batch
dataset: generic

# 数据目录
data_dir: {output_path.absolute()}

# 流域文件
train_basin_file: {train_basin_file.absolute()}
validation_basin_file: {validation_basin_file.absolute()}
test_basin_file: {test_basin_file.absolute()}

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
epochs: 100
batch_size: 256
optimizer: Adam
loss: MSE

# 学习率调度
learning_rate:
  0: 0.001
  30: 0.0005
  60: 0.0001

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
validate_every: 10
validate_n_random_basins: 3

# 正则化
clip_gradient_norm: 1.0

# 日志和保存
log_interval: 20
log_tensorboard: true
log_n_figures: 3
save_weights_every: 20

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
    
    config_file = output_path / "haihe_subwatersheds_config.yml"
    with open(config_file, 'w', encoding='utf-8') as f:
        f.write(config_content)
    print(f"✅ 创建配置文件: {config_file}")
    
    # 6. 创建使用说明
    print(f"\n📖 创建使用说明...")
    
    readme_content = f"""# NeuralHydrology海河流域子流域批量训练

## 📁 目录结构
```
{output_path.name}/
├── time_series/
│   ├── haihe_sub_1_lump_camels_forcing.txt
│   ├── haihe_sub_1_streamflow_qc.txt
│   ├── haihe_sub_2_lump_camels_forcing.txt
│   ├── haihe_sub_2_streamflow_qc.txt
│   └── ... (其他子流域)
├── attributes/
│   ├── haihe_sub_1_attributes.csv
│   ├── haihe_sub_2_attributes.csv
│   └── ... (其他子流域属性)
├── train_basins.txt
├── validation_basins.txt
├── test_basins.txt
├── haihe_subwatersheds_config.yml
└── README.md
```

## 🚀 使用方法

### 1. 批量训练
```bash
python neuralhydrology/nh_run.py train --config-file haihe_subwatersheds_config.yml --gpu 0
```

### 2. 评估模型
```bash
python neuralhydrology/nh_run.py evaluate --run-dir runs/haihe_subwatersheds_batch_*/ --period test
```

## 📊 子流域信息

### 训练集
{chr(10).join([f"- {basin_id}" for basin_id in train_basins])}

### 验证集
{chr(10).join([f"- {basin_id}" for basin_id in validation_basins])}

### 测试集
{chr(10).join([f"- {basin_id}" for basin_id in test_basins])}

## 🎯 优势

1. **多流域训练**: 提高模型泛化能力
2. **合理流域大小**: 每个子流域面积适中，便于学习
3. **批量处理**: 一次性训练多个流域
4. **性能对比**: 可以比较不同子流域的模型性能

## ⚠️ 注意事项

1. **径流数据**: 当前使用模拟数据，需要真实观测数据
2. **流域选择**: 可以根据模型性能调整子流域选择
3. **参数调优**: 建议先在小规模数据上测试参数

生成时间: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}
"""
    
    readme_file = output_path / "README.md"
    with open(readme_file, 'w', encoding='utf-8') as f:
        f.write(readme_content)
    print(f"✅ 创建使用说明: {readme_file}")
    
    print(f"\n🎉 子流域数据处理完成!")
    print(f"📁 输出目录: {output_path}")
    print(f"📊 处理子流域数量: {len(basin_ids)}")
    print(f"📄 主要文件:")
    print(f"  - 气象数据: {len(basin_ids)} 个文件")
    print(f"  - 径流数据: {len(basin_ids)} 个文件")
    print(f"  - 流域属性: {len(basin_ids)} 个文件")
    print(f"  - 配置文件: haihe_subwatersheds_config.yml")
    print(f"  - 使用说明: README.md")
    
    return True

def create_simulated_streamflow(df_meteo, basin_id):
    """
    创建模拟径流数据
    
    Parameters
    ----------
    df_meteo : pd.DataFrame
        气象数据
    basin_id : str
        流域ID
        
    Returns
    -------
    pd.DataFrame
        径流数据
    """
    
    # 简化的径流模拟模型
    # Q = α * P * exp(-β * (T - T0))
    
    alpha = 0.3  # 径流系数
    beta = 0.1   # 温度系数
    T0 = 0       # 参考温度 (°C)
    
    # 计算径流
    precip = df_meteo['prcp(mm/day)'].values
    temp = df_meteo['tmean(C)'].values
    
    # 避免除零和负值
    temp = np.maximum(temp, -10)  # 最低温度限制
    precip = np.maximum(precip, 0)  # 降水不能为负
    
    # 径流计算
    streamflow = alpha * precip * np.exp(-beta * (temp - T0))
    
    # 创建径流DataFrame
    df_streamflow = pd.DataFrame({
        'Year': df_meteo['Year'],
        'Mnth': df_meteo['Mnth'],
        'Day': df_meteo['Day'],
        'QObs(mm/d)': streamflow
    })
    
    return df_streamflow

def main():
    """主函数"""
    print("🔄 子流域数据转换为NeuralHydrology格式")
    print("=" * 50)
    
    # 设置路径
    gee_data_dir = "Haihe_Subwatersheds_Data"  # GEE导出数据目录
    output_dir = "data/haihe/subwatersheds_neuralhydrology"  # 输出目录
    num_subwatersheds = 5  # 子流域数量
    
    # 检查输入目录
    if not Path(gee_data_dir).exists():
        print(f"❌ GEE数据目录不存在: {gee_data_dir}")
        print("💡 请先运行GEE代码导出子流域数据")
        return
    
    # 执行转换
    success = process_subwatersheds_data(gee_data_dir, output_dir, num_subwatersheds)
    
    if success:
        print(f"\n✅ 转换成功!")
        print(f"🚀 现在可以使用以下命令开始批量训练:")
        print(f"python neuralhydrology/nh_run.py train --config-file {output_dir}/haihe_subwatersheds_config.yml --gpu 0")
    else:
        print(f"\n❌ 转换失败!")

if __name__ == "__main__":
    main()
