# 状态轨迹叠加三段真实参数

这些图把“生成真实状态、真实流量和带噪观测流量的真实参数”直接叠加到
状态更新对比图上。顶部色条给出三个180天参数阶段；所有状态面板使用
同色半透明背景，并在第180—181天和第360—361天之间画切换边界。

曲线分别是：真实状态、同化前进行状态和协方差交互后发布的唯一全局
后验状态、同化前不进行状态和协方差交互但仍发布唯一全局后验状态、
以及完全不读取流量观测的状态。

图件使用第一个预先登记噪声区块的原始轨迹，不平滑、不取中位数、
不跨区块汇总。这里没有重新运行同化或预报，也不产生新的科学比较
结论。

- `five_hydrologic_states_with_true_parameter_stages.png`：五个水文状态主图。
- `all_15_states_with_true_parameter_stages_trial_1.png`至
  `all_15_states_with_true_parameter_stages_trial_3.png`：包含十个汇流记忆
  状态的完整图。
- `stage_schedule.csv`：三次真实试验的九个参数阶段。
- `plotted_data.npz`：实际绘图数组。
- `verification.json`：独立核验结果。
