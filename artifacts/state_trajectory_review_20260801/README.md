# 每日状态过程线审阅附件

## 主图

`five_hydrologic_state_trajectories_three_scenarios.png`是面向水文状态审阅
的主图，只显示积雪、融雪水、土壤水、上层地下水和下层地下水五个
状态。三列是同一组降雨、蒸散和随机扰动下，三套真实参数排列场景。

其余15状态图是完整计算状态的诊断附件。里面的十个“汇流记忆”只是
程序为延迟汇流而保存的当日及前九日原始汇流量，不是十个额外的水文
蓄水状态，不应代替五个水文状态主图。

## 曲线定义

- 真实状态：封存合成实验的同日15维真实状态。
- 完全交互：三个相同固定参数模型在更新前交互状态和协方差，更新后
  发布的唯一全局后验状态。
- 不交互：相同三个模型不交互状态和协方差，但仍执行相同概率递推、
  观测更新和全局后验合成后得到的唯一全局后验状态。
- 完全不矫正：封存合成实验中的开环状态，不读取流量观测进行状态更新。

全部图覆盖540个同化日和15个状态，没有平滑、抽样或按距离真实参数
阶段边界多少天分组。灰色竖线只标出合成真实参数的阶段边界。

## 图件

`raw_registered_block_001_truth_trial_1.png`至
`raw_registered_block_001_truth_trial_3.png`显示第一个预先登记区块的
三个真实参数试验。选择第一个登记区块是预先固定的展示规则，不按结果
挑选。

`median_all_8_blocks_truth_trial_1.png`至
`median_all_8_blocks_truth_trial_3.png`显示全部八个预先登记区块在同一天
的中位数，用于查看总体形态；中位线不是某个区块的原始轨迹。

## 数据来源

- 两种状态更新方法与真实状态：
  `results/23_hbv_multilead_joint_uncertainty/g3_fixed_process_state_interaction_global_posterior_audit_v01/evidence.npz`
- 完全不矫正状态：
  `results/23_hbv_multilead_joint_uncertainty/g3_ideal_gate_param_switch_v01/evidence.npz`
- 状态实验数据文件SHA-256：
  `22f1b99ee0cf537e1aa7c9b414662c0b390510f2dc0d6b07bf538dd6dda33a04`
- 封存合成实验数据文件SHA-256：
  `77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67`
