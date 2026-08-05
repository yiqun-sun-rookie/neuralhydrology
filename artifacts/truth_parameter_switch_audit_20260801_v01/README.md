# 合成真实参数三阶段切换审计

## 结论

封存真值生成器已经按三个180天阶段切换用于生成真实状态和真实流量的
参数。三次真实试验都只在第180—181天和第360—361天之间切换，过程
噪声方案固定不变，15维真实状态不在切换点重新初始化。

用户指出的状态异常真实存在。第二次真实试验在第360—361天、第三次
真实试验在第180—181天从“等效异参方案1”切换到“校准中心参数”时，
土壤水状态分别单日下降445.5222和433.3963；对应非切换日绝对变化的
第95百分位分别只有22.1108和22.0184，边界变化分别是其20.15倍和
19.68倍。

直接原因是土壤最大容量参数从565.9438降至115.4114。模型在同一日的
确定性推进中将超过新容量的土壤水转移到上层蓄水并参与快速出流；这
不是绘图汇总造成的，也不是事后状态投影造成的。过程噪声随后进一步使
土壤水分别变化-9.9359和-11.7482。

因此，这个封存三阶段设计可以作为“参数突变压力试验”，但不能未经
额外分层就解释成一般、平滑的水文状态变化。本文档和图件不比较状态
更新方法，也不包含预报证据。

## 图件

- `truth_parameter_switch_audit_all_trials.png`：第一个预先登记噪声区块的
  三次真实试验并列图。顶部颜色条给出真实参数阶段，随后为真实流量与
  带噪观测流量、五个水文蓄水状态以及十个汇流记忆状态。
- `truth_parameter_switch_audit_trial_1.png`至
  `truth_parameter_switch_audit_trial_3.png`：同一内容的单试验放大图。

所有图均覆盖540个同化日，不跨区块汇总，不取中位数，不平滑。

## 数值附件

- `stage_schedule.csv`：九个“真实试验×阶段”的参数日程。
- `true_parameter_vectors.csv`：三套13维真实参数向量。
- `boundary_state_change_audit.csv`：每次切换、每个状态的单日变化及非
  切换日参照分布。
- `plotted_data.npz`：实际绘入图件的原始数组副本。
- `verification.json`：独立逐元素核验结果。

## 证据和边界

- 封存证据：
  `G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_ideal_gate_param_switch_v01\evidence.npz`
- 封存证据SHA-256：
  `77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67`
- 真值生成循环：
  `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability.py`
- 土壤容量和超额水转移：
  `G:\wt\id23-readout\src\hbv_joint_uncertainty\hbv_adapter.py`

独立核验确认实际绘图数组与封存源逐元素最大绝对差为0；观测流量等于
真实流量加封存观测噪声的最大绝对残差为
`3.837208328860697e-15`。
