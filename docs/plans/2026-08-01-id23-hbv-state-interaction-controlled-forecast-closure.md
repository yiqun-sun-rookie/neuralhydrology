# HBV状态交互单因素确定性预报实验收口

## 结论

实验`g3_fixed_process_state_interaction_controlled_forecast_v01`没有确认完全
交互能够改善第一日至第七日的流量预报。七个预见期的完全交互均方根
误差点估计均比不交互低`1.214613%`至`1.667257%`，达到至少`1%`的
点估计门槛；但“完全交互均方误差减去不交互均方误差”的七个配对
`95%`区间都跨过零，因此七个预见期均未通过预定双门槛。

该结论只属于HBV降雨—径流模型的合成机制实验，不属于Wageningen
Lowland Runoff Simulator（瓦赫宁根低地径流模拟模型）或真实流域证据。

## 公平比较合同

- 唯一变化因素：同化前是否进行状态和协方差交互；
- 固定因素：相同三个固定参数模型、`process_2`过程噪声、初始条件、
  观测、气象强迫、概率预测与更新、全局后验合成和目标；
- 两种方法各使用一个唯一的15维全局后验状态；
- 两种方法统一使用固定`trained_center`参数；
- 每种方法每个起报日只发出一条确定性轨迹，不传播协方差、采样点或
  模型条件候选轨迹，起报后不使用未来流量观测；
- 覆盖八个匹配输入与噪声区块、三个真实参数场景、540个逐日起报点和
  第一日至第七日；
- 主指标排除跨越下一真实参数阶段的目标；
- 配对区间以八个匹配区块为重采样单位，重采样20,000次，随机种子为
  `20260801`。

## 全阶段结果

相对变化定义为“完全交互均方根误差除以不交互均方根误差再减一”；
负值表示完全交互点估计更低。配对差值定义为完全交互均方误差减去
不交互均方误差。

| 预见期 | 完全交互均方根误差 | 不交互均方根误差 | 相对变化 | 配对均方误差差值95%区间 | 判断 |
|---|---:|---:|---:|---:|---|
| 第1日 | 5.603650 | 5.672550 | -1.214613% | [-2.846768, 1.459109] | 未达到改善标准 |
| 第2日 | 8.058687 | 8.163467 | -1.283516% | [-5.917808, 2.897124] | 未达到改善标准 |
| 第3日 | 7.960042 | 8.069992 | -1.362463% | [-5.607804, 2.362567] | 未达到改善标准 |
| 第4日 | 7.901089 | 8.011972 | -1.383959% | [-5.398050, 2.098812] | 未达到改善标准 |
| 第5日 | 7.858712 | 7.977347 | -1.487146% | [-5.318128, 1.728623] | 未达到改善标准 |
| 第6日 | 7.815068 | 7.945043 | -1.635920% | [-5.347263, 1.262620] | 未达到改善标准 |
| 第7日 | 7.778596 | 7.910484 | -1.667257% | [-5.314211, 1.104568] | 未达到改善标准 |

每个区块保留的同阶段样本数从第一日的`1614`递减到第七日的`1578`；
八个区块合计样本数从`12912`递减到`12624`。

## 测试和独立核验

- 正式运行前计划指定的聚焦与相关回归测试：`20 passed`；
- 正式运行后包含原状态实验运行器和核验器的回归测试：`26 passed`；
- 唯一警告是仓库既有的未知pytest配置项`collect_ignore_glob`；
- 正式运行器与独立参考传播抽查`288`条轨迹，最大绝对差
  `5.329070518200751e-15`；
- 独立核验器未导入正式运行器、正式统计模块或正式确定性预报函数；
- 独立核验重算全部起报状态、轨迹、目标、同阶段掩码、均方根误差、
  区块均方误差、20,000次配对区间和判断；
- 独立核验最大绝对差为`1.4210854715202004e-14`，小于容差`1e-10`；
- 独立核验状态：`passed`。

## 证据路径

- 冻结配置：
  `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\configs\g3_fixed_process_state_interaction_controlled_forecast_v01.json`
- 配对统计：
  `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\state_interaction_controlled_forecast.py`
- 正式运行器：
  `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\run_g3_fixed_process_state_interaction_controlled_forecast.py`
- 独立核验器：
  `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\verify_g3_fixed_process_state_interaction_controlled_forecast.py`
- 结果目录：
  `G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_controlled_forecast_v01`
- 正式汇总：`summary.json`
- 原始数组：`evidence.npz`
- 独立核验：`independent_verification.json`
- 运行环境：`environment.json`
- 文件清单：`checksums.json`

## 正式结果文件散列值

- `checksums.json`：`c028a69f4db995584d62f040fa2f2a9dffe182b19c62c516dab23bce177d65d7`
- `config_snapshot.json`：`a308e840f5800e52f3000188dc0d3fc7b7fc6b237a1aa2c5db237a3c4ce3b9eb`
- `environment.json`：`c8e91bbee3cb3193b9fcbbc701c23f15d1ef2b147e84906c87d85489d3713a5b`
- `evidence.npz`：`0653b61af273a170ff09c396ad8ae26b8c11beef3107c06cb95a268837fa0892`
- `independent_verification.json`：`679e7b0c13dfe588d00940a5aabe5ab4daf975bf14840ad0c7e33217cea61561`
- `summary.json`：`bfddb69cb7f58110fe7de7994e7a902966c4b910b4b01a042240e72938113155`

## 解释限制

参数切换后七天的局部实验只说明突变后的短窗口，不能替代本次全阶段
结果。本次结果也只说明冻结的三个参数候选、过程噪声、合成强迫和
评价合同下，状态和协方差交互没有在任一预见期达到预定改善证据标准；
它不能证明不交互在其他候选配置、其他噪声、其他水文模型或真实流域中
普遍更好。
