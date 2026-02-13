"""
分析CAMELSH训练过程并给出改进建议
"""

import pandas as pd
import numpy as np

def main():
    # 验证指标记录
    data = [
        (2, 0.14136, 0.09326),
        (4, 0.21141, 0.35475),
        (6, 0.27795, 0.30597),
        (8, 0.47724, 0.50731),
        (10, 0.53570, 0.58023),
        (12, 0.55748, 0.59116),
        (14, 0.51627, 0.53193),
        (16, 0.28868, 0.37798),
        (18, 0.58737, 0.61510),
        (20, 0.57506, 0.58840),
        (22, 0.55622, 0.56856),
        (24, 0.53616, 0.64834),
        (26, 0.53574, 0.55515),
        (28, 0.50164, 0.53318),
        (30, 0.54927, 0.62740),
    ]
    
    df = pd.DataFrame(data, columns=['Epoch', 'NSE', 'KGE'])
    
    print('='*70)
    print('CAMELSH 训练过程分析')
    print('='*70)
    
    print('\n【1】训练过程记录')
    print('-'*50)
    print(df.to_string(index=False))
    
    best_nse_epoch = df.loc[df.NSE.idxmax(), 'Epoch']
    best_kge_epoch = df.loc[df.KGE.idxmax(), 'Epoch']
    
    print(f'\n最佳NSE: {df.NSE.max():.4f} (Epoch {best_nse_epoch})')
    print(f'最佳KGE: {df.KGE.max():.4f} (Epoch {best_kge_epoch})')
    
    # 分析训练曲线
    print('\n【2】训练曲线分析')
    print('-'*50)
    
    # 检测异常波动
    nse_diff = df['NSE'].diff().abs()
    max_drop = nse_diff.max()
    drop_epoch = df.loc[nse_diff.idxmax(), 'Epoch']
    
    print(f'NSE最大波动: {max_drop:.4f} (Epoch {drop_epoch})')
    print(f'Epoch 14->16: NSE从0.52下降到0.29 (异常波动!)')
    print(f'Epoch 16->18: NSE从0.29恢复到0.59 (恢复正常)')
    
    # 后期稳定性
    late_nse = df[df['Epoch'] >= 18]['NSE']
    print(f'\nEpoch 18-30 NSE范围: {late_nse.min():.4f} ~ {late_nse.max():.4f}')
    print(f'后期波动: {late_nse.std():.4f}')
    
    print('\n【3】保存的文件')
    print('-'*50)
    print('''
runs/camelsh_hourly_optimized_2025_1201_1339_ep30/
├── config.yml                  # 配置文件
├── output.log                  # 训练日志
├── events.out.tfevents.*       # TensorBoard日志
├── model_epoch*.pt             # 模型权重 (5,10,15,20,25,30)
├── optimizer_state_epoch*.pt   # 优化器状态
├── img_log/                    # 预测图像
│   └── Streamflow_freq1h_epoch*.png
├── train_data/                 # 训练数据标准化参数
│   └── train_data_scaler.yml
└── test/                       # 测试结果
    └── model_epoch030/
        ├── test_metrics.csv    # 测试指标
        └── test_results.p      # 详细结果
''')
    
    print('\n【4】模型改进空间分析')
    print('-'*50)
    print('''
┌─────────────────────────────────────────────────────────────────────┐
│ 当前结果: NSE=0.56, KGE=0.61                                         │
│ 目标参考: CAMELS-US日模型 NSE=0.74                                   │
│ 差距分析: 小时模型天然比日模型难，0.56是合理的起点                   │
└─────────────────────────────────────────────────────────────────────┘

【高优先级改进】

1. 🔧 使用最佳Epoch模型
   - 当前使用Epoch 30 (NSE=0.55)
   - 建议使用Epoch 18 (NSE=0.59) - 提升约4%
   
2. 📊 增加训练数据
   - 当前: 5年训练 (2010-2014)
   - 建议: 扩展到10年 (2002-2014) - 预计提升5-10%
   
3. 🔄 序列长度优化
   - 当前: 168小时 (7天)
   - 尝试: 336小时 (14天) 或 720小时 (30天)
   - 小时数据可能需要更长记忆

【中优先级改进】

4. 🧠 模型架构
   - 尝试双层LSTM (num_layers=2)
   - 尝试更大hidden_size (256)
   - 尝试EA-LSTM (考虑静态属性的注意力)

5. 📉 正则化
   - 当前: output_dropout=0.0
   - 建议: 添加dropout=0.1-0.2
   - 缓解Epoch 16的异常波动

6. ⏰ 学习率调度
   - 当前: 阶梯式 (0.003->0.001->0.0005)
   - 尝试: 余弦退火 (cosine annealing)

【低优先级改进】

7. 📈 自回归 (AR)
   - 添加历史径流作为输入
   - 注意: 可能引入数据泄露风险

8. 🔀 多时间尺度
   - 同时使用小时和日尺度特征
   - Multi-scale LSTM

9. 🌍 迁移学习
   - 先在CAMELS-US日数据上预训练
   - 再微调到CAMELSH小时数据
''')

    print('\n【5】快速提升建议')
    print('-'*50)
    print('''
立即可做的改进 (预计提升3-5%):

1. 使用最佳模型: 
   cp runs/.../model_epoch018.pt -> best_model.pt
   (如果保存了的话，否则从epoch020开始)

2. 扩展训练时间:
   train_start_date: "01/01/2002"
   train_end_date: "31/12/2014"  # 13年数据

3. 增加序列长度:
   seq_length: 336  # 14天

4. 添加Dropout:
   output_dropout: 0.1

预计改进后: NSE 0.60-0.65
''')

if __name__ == '__main__':
    main()


