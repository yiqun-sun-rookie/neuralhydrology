# 历史连续多尺度气象模型正式版本09训练目标包审核

## 结论

- 531流域训练目标包：**审核通过**；
- 正式训练、正式预测、随机划分和正式评分：**继续禁止执行**；
- 本结论只证明训练目标包可追溯且不包含正式评价期目标，不代表任何模型有效。

## 授权和提交

- 用户批准文本：`批准仅生成正式531流域训练目标包；其他正式授权继续关闭`；
- 批准文本无换行UTF-8 SHA-256：
  `56d5fce10ff6466ba06a574184684e218b3c0c0662ceab06c37fdc7b684e6587`；
- 生成提交：`7c6a95f347d04e122793a19902b4a60124f0d4ba`；
- 关闭授权提交：`2676f48f6ce4c9cb92d7614dac13fb799cd4b941`；
- 生成时只有`formal_target_bundle_generation=true`；训练、正式预测和正式评分均为`false`，
  `formal_evaluation_target_access=false`；
- 生成完成后目标构建授权恢复为`false`，全部正式授权均已关闭。

## 产物

- 目标文件：
  `results/26_historical_band_experts/formal_v09/inputs/training_targets.csv`；
- 目标文件大小：`68,631,401`字节；
- 目标文件SHA-256：
  `6abadf7172f1c8ebd48122a8abf68985d7d4f94b8c894371270208eeb45f2ebb`；
- 清单文件：
  `results/26_historical_band_experts/formal_v09/inputs/training_targets.manifest.json`；
- 清单文件大小：`248,669`字节；
- 清单文件SHA-256：
  `3061d548fa0b9c81c8e3e25f0dbdd8cfbdb347aaea965ac6f6400c5f09da13e8`；
- 正式目录只有上述两个文件，临时文件为0。

## 独立数值复核

- 列严格为`basin,date,qobs`；
- 流域数：`531`，顺序与冻结流域文件完全一致；
- 每流域连续日数：`3,288`；
- 总行数：`1,745,928`；
- 最小日期：`1999-10-01`；
- 最大日期：`2008-09-30`；
- 所有目标均有限且非负；最小值`0`，最大值`459.97135682967513`，零值`51,403`个；
- 独立从原始流量重算全部`1,745,928`个训练值，与目标文件逐字符串一致，最大绝对差为`0`。

## 源文件和源码追溯

- 源文件记录数：`1,062`，每个流域恰有一个Maurer气象文件和一个原始流量文件；
- 当前源文件逐个重算SHA-256，差异数为`0`；
- 源文件清单规范化SHA-256：
  `9c9835e2524a666d5831f7c1babff90dd18ea5a8efc94d51ba1b01bececd7339`；
- 生成源码树包含8个文件，均与生成提交中的Git对象一致；
- 生成源码树SHA-256：
  `ac39fa423a5ca6997e7e3504fa877f96e4f9eb869f0d2669e0674b8a8bedad4f`；
- 生成协议规范化SHA-256：
  `f60161ffa76848179fd83d82eb92b6c2ba754270c0f5e16695e81aa237a78bc5`；
- 冻结流域文件SHA-256：
  `cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85`。

## 正式评价期屏蔽

- 正式评价期日期行数：`1,939,212`；
- 这些行只扫描流域号和日期前缀；流量余量切分次数为`0`，数值解析次数为`0`；
- 清单记录`formal_evaluation_rows_emitted=0`；
- 清单记录`formal_evaluation_qobs_parsed=0`；
- 清单记录`candidate_raw_streamflow_files_read=0`。

## 测试和停止边界

- 开放阶段资源、运行时和目标构建回归：`34 passed, 2 deselected, 1 warning`；
- 关闭授权后的直接受影响回归：`49 passed, 1 deselected, 1 warning`；
- 唯一警告为仓库既有的未知pytest配置项`collect_ignore_glob`；
- 未启动训练、正式预测、随机数抽取或正式评分；
- 后续使用前必须再次核对目标和清单SHA-256，并完成正式输入封存；
- 目标包审核通过不能替代训练、预测或评分的独立批准。
