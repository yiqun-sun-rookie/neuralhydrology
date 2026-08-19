# 交接：CAMELS-US 土壤最大蓄水容量九路径方法——03B 二十项机制检查前（2026-08-11）

**当前结论：完整状态交互和守恒容量映射明显改善了事件辨认与多类别概率误差，但在少数流域—历史组合上产生灾难性过度自信，正式门仍未通过。新的“九条来源到目标路径分别观测、观测后再合并”方法已经完成代码、186 项相关测试和只读内存技术预检，但尚无正式实验结果，科学状态仍为 HOLD。**

本文件取代 `HANDOFF_20260809_CAMELS_NOISE_ONLY_NEXT.md`，成为 CAMELS-US 当前活动线入口。旧文件保留为早期参数实验和过程噪声线的历史证据；过程噪声线没有通过完整预登记辨认门，不是当前优先步骤。

## 一、整体目标与当前阶段定位

### 1. 最终目标

论文项目 `imm-save` 位于 `G:\github\pycharm\projects\paper-imm-variable-params`。最终问题是：交互多模型方法能否在水文状态更新中处理参数不确定性和噪声不确定性，并进一步产生可靠的完整状态估计和预报价值。

CAMELS-US 本线使用 531 个真实率定参数域和真实气象强迫，但真值仍由同一简化概念性降雨—径流模型生成。当前只检验已知候选制度能否被辨认，是后续状态精度、预报价值和真实观测同化之前的必要条件。

### 2. 当前阶段

当前阶段只研究土壤最大蓄水容量参数 `parFC` 的候选切换。目标是判断既有失败是否来自“在看见当天观测前，过早把不同历史路径压成一个目标候选状态”。

当前拟比较同一 10 个失败筛选的流域—种子任务：

- **基线方法 C：**完整跨候选状态交互、守恒土壤容量状态映射、观测前按目标候选合并。
- **改进方法 P：**每天展开 3×3=9 条“昨日来源候选→今日目标候选”路径；每条路径独立完成守恒状态映射、推进和观测更新，然后在观测后先合并为三个目标候选，再合成唯一的概率加权十五状态全局后验。

改进方法是交互多模型方法的一步路径保留扩展，不是原样标准交互多模型公式。九路径直接合成只作数值诊断；唯一主状态、状态评价和主预测必须使用三个目标候选逐级合成的十五状态全局后验。

本阶段仍只检验参数候选概率，不检验完整状态精度或预报价值。

## 二、固定实验合同

- 三个参数候选：每个流域率定中心土壤最大蓄水容量、中心值乘 `0.5`、中心值乘 `2.0`；其余 12 个水文参数相同。
- 七阶段真值顺序：中心→一半→两倍→中心→两倍→一半→中心，即候选索引 `[0,1,2,0,2,1,0]`；每阶段 180 天，总计 1260 天。
- 转移矩阵：对角线 `0.98`，两个非对角元素各 `0.01`。
- 真实过程噪声：只作用于下层地下水状态的乘性对数正态噪声，标准差参数固定为 `0.02`，不切换。
- 滤波器过程协方差：只作用于下层地下水状态、固定模式，缩放系数 `3e-8`；该值是协方差缩放系数，不是真实噪声标准差。
- 观测误差制度固定；滤波器观测方差乘数为 `1`。
- 设计种子只允许 `{0,1}`。当前 10 个任务为：`02096846/s0`、`02096846/s1`、`02193340/s0`、`02193340/s1`、`02221525/s1`、`02349900/s1`、`05413500/s0`、`05501000/s1`、`07145700/s0`、`07145700/s1`。
- 每个方法 10 个任务，共 20 个任务；不得拼接旧版本 03 或 03A 的基线结果。
- 科学评分切片固定为每任务数组索引 `180:1260`，每个方法共有 10,800 个等权评分日。
- 普通浮点候选概率用于状态混合和下一日递归；稳定对数概率只保存和评分，不得复活已经下溢为零的普通路径。

## 三、限制、成功标准和停止条件

### 1. 写入、种子和主张边界

- 唯一可写代码位置：`G:\wt\camels-rising`，分支 `codex/camels-rising-half-recal`。
- 主仓库 `G:\github\pycharm\projects\neuralhydrology` 一律只读；不得清理当前脏工作树。
- 未经明确要求不得提交、推送、删除结果、覆盖输出或修改主仓库。
- 种子 `{0,1}` 已用于设计和诊断，只能产生探索性证据。种子 `{2,3}` 仍保留给未来冻结后的验证；当前禁止使用。
- 禁止运行 90 或 531 流域、禁止冻结版本 02、禁止外推完整状态精度、预报价值、真实观测同化价值、唯一真实参数或所有参数的可辨认性。
- 版本 03B 是本机制的最后技术修订。若其登记技术门失败，不得自行创建版本 03C。

### 2. 二十项机制检查的技术完整性门

以下条件必须全部通过，才允许计算科学继续指标：

1. 基线和改进方法各 10 项，20/20 完成；基线逐值复现登记来源。
2. 概率有限、非负、逐日归一；真值无裁剪；创新协方差可用。
3. 第 0 日概率、三个候选的十五状态和协方差与独立初始矩清单逐位相同。
4. 独立核验器从普通来源概率、转移矩阵和九路径似然重建九路径权重、三个目标候选、唯一全局后验及跨日递归；与生产输出逐位相同。
5. 每一个目标内层和全局外层的高精度均值、协方差误差比都不大于 `1`。
6. 每日真实土壤最大蓄水容量与候选参数表独立匹配，并重建出 `[0,1,2,0,2,1,0]`；评分切片严格为 `180:1260`。
7. 独立核验器写出 `verification_status=passed`。

### 3. 科学继续门

只有技术门全部通过后，改进方法 P 才必须同时满足：

1. 真实候选稳定负对数概率严格大于 `100` 的日数少于基线方法 C；
2. 真实候选稳定负对数概率算术平均数低于基线方法 C。

两项同时通过，只允许申请准备 90 流域设计种子配置；不等于参数切换稳定辨认，也不自动授权 90 或 531 流域运行。

### 4. 强制停止

- 运行前：配置、初始矩清单或运行清单不存在；任一输入、实现、测试、Python 可执行文件、运行环境或配置散列变化；任务身份错误；出现种子 2、3；新输出或日志已经存在；输出越出 `results/23_camels_switch_confirmation` 或进入来源、版本 03、版本 03A 证据根。
- 运行中：任一任务失败后立即停止新增提交；已启动任务安全收尾；原子保留部分证据并以非零状态退出。
- 运行后：20/20 未完成、任何技术门或独立核验失败，立即 HOLD；不得改变阈值后重跑。

## 四、有效结果和明确结论

以下数字全部来自合成真值和设计种子 `{0,1}`，均为探索性。

### 1. 原始 531 流域参数切换确认 ND01：失败基线

- 531 流域×2 种子=1062 任务，6372 个切换事件；1062/1062 运行成功。
- 总体事件通过率 `0.46139`；切换到中心参数 `0.28955`，切换到两侧参数 `0.54732`；最差方向“一半→中心”为 `0.27872`。
- 第 180 天后多类别 Brier 分数 `0.82068`，差于均匀概率基线 `2/3`；真实候选负对数概率 `19.60703`。
- 概率有限、逐日归一，真值未改变。失败不是任务崩溃造成的。

结论只限于当时的土壤最大蓄水容量候选方案，不能外推为所有参数、状态、预报或噪声辨认失败。

### 2. 过程噪声单独切换 01A：概率质量较好，但完整辨认门未通过

- 90 流域×2 种子=180 任务，180/180 成功。
- 事件通过 `649/1080=0.60093`，低于要求 `0.8`；最差方向 `2→1` 为 `0.38889`，低于每方向要求 `0.7`；种子事件一致率 `0.66481`，低于要求 `0.8`。
- 多类别 Brier 分数 `0.22135`、真实候选负对数概率 `0.40387`、分类校准误差 `0.06128`，均通过登记的概率质量门。

明确结论：稳定阶段的噪声候选概率优于均匀基线，但不能称为稳定识别过程噪声切换。

### 3. 参数状态交互 01B：总体改善，但过度自信导致 HOLD

90 流域、三种方法、种子 0、1，共 540/540 任务和 3240 个事件全部完成：

| 方法 | 事件通过 | 通过率 | 多类别 Brier | 稳定真实候选负对数概率 |
|---|---:|---:|---:|---:|
| 历史分组状态+旧直接投影 | 503/1080 | 0.46574 | 0.82036 | 277.71510 |
| 完整状态交互+旧直接投影 | 563/1080 | 0.52130 | 0.60424 | 356.70813 |
| 完整状态交互+守恒容量处理（基线 C） | 706/1080 | 0.65370 | 0.35797 | 9543.50655 |

基线 C 的最差方向仍为“一半→中心”`51/180=0.28333`；“中心→两倍”`0.40556`，“一半→两倍”`0.48333`。真实候选普通概率为零的评分日有 `2044/194400`。

明确结论：完整状态交互和守恒容量处理使事件通过数和 Brier 分数在数值上明显改善，但方向稳健性和概率尾部失败，两个预登记门均未通过。

### 4. 过度自信诊断 02A：状态路径主导

选择 01B 中任务级稳定真实候选负对数概率大于 `1000` 的 10 个任务；10/10 完成，包含 37,800 个候选—日和 1974 个每日负对数概率大于 `100` 的严重日。

- 1974/1974 严重日均由预测残差平方项主导，创新方差项主导为 0 日。
- 严重日赢家容量全部高于真值，真值候选全部高估观测。
- 赢家来源在真实目标候选中的条件权重中位数约为 `1`；`83.49%` 的严重日超过 `0.99`。
- 守恒映射把超额土壤水转入上层地下水，中位转移量 `137.2105` 毫米，形成虚假高流量预测和自强化后验锁定。

支持的解释：在这 10 个失败筛选任务的严重日中，极端似然惩罚由预测残差平方项主导；状态路径证据支持观测前压缩参与后验锁定。创新方差项不是这些严重日的主导项。尚不能据此认定似然降温或噪声膨胀是解法。

### 5. 路径方法版本 03 和 03A：可审计的技术失败，无科学结果

- 版本 03：计划 20，提交 14；基线成功 10，改进方法失败 4，6 项未提交。首次失败是 `07145700/s1` 第 39 天，直接九路径和三目标逐级状态差 `1.8189894035458565e-12`，相对状态尺度 `8.1931e-16`。
- 版本 03A：计划 20，提交 12；基线成功 10，改进方法失败 2，8 项未提交。`07145700/s0` 第 435 天协方差差 `1.6370904631912708e-11`、相对差 `4.3998e-15`、36 个浮点最小间隔；`05501000/s1` 第 1194 天状态差 `1.3642420526593924e-12`、相对差 `5.5277e-16`、3 个间隔。在首个协方差失败点，80 位小数重算的直接与逐级残差仅为 `3.4e-75`，未发现公式差异。
- 两次运行均没有任何改进方法概率文件，也没有科学汇总。旧输出集合和散列已复核不变，不得修改、删除或与新结果拼接。

明确结论：它们暴露的是过严的双精度重排纯绝对差容差门，不是路径方法的科学失败或通过。

### 6. 最终技术修订 03B：实现完成，科学效果未验证

- 相关五个测试文件合计 `186 passed, 1 warning in 67.66s`，标准错误日志为 0 字节。警告只是仓库既有未知 `collect_ignore_glob` 配置项。
- 两个旧失败任务均已完成 1260 天只读内存逐级重建和高精度诊断：总计 6574 个活动目标混合、2520 个全局混合和 986 个零质量目标层；最大均值误差比 `0.12499989373789755`，最大协方差误差比 `0.022698684932313147`，均低于上限 `1`。
- 上述两任务的高精度数字没有单独落盘原始证据文件，只能视为内存技术诊断；正式版本 03B 独立核验必须重新检查全部实际输出。
- 目前没有版本 03B 配置、独立初始矩清单、运行清单、结果目录或运行进程。

可复现性分类：ND01、过程噪声 01A、参数状态交互 01B 和诊断 02A 可审计、可重跑但仅为探索性；版本 03、03A 是可审计的技术失败且无科学汇总；版本 03B 只有可审计的实现和技术预检，没有正式实验结果。

## 五、当前代码、证据和路径

### 1. 工作树与运行环境

- 工作树：`G:\wt\camels-rising`
- 分支：`codex/camels-rising-half-recal`
- 提交：`61e938b3a89f648e460a20e6f03e005bdc9fca4a`
- 工作树状态：98 项，含 4 个已跟踪修改和 94 个未跟踪条目；必须全部保留。其中新增的第 98 项是本交接文件本身。
- 版本 03B 相关 Python 进程：0。
- Python：`C:\Users\yiqun\anaconda3\python.exe`，SHA-256 `c98caee82c66433f0e89d4abbf152b39a7dc2e99979b28dcb021598b4e3f5642`。
- 固定环境：CPython `3.11.5` Anaconda 构建，`MSC v.1916 64 bit (AMD64)`，NumPy `1.26.4`，IEEE 754 小端双精度，尾数 53 位，`rounds=1`，无 `math.fma`。

### 2. 当前关键文件与 SHA-256

| 用途 | 路径 | SHA-256 |
|---|---|---|
| 最终 03B 预注册 | `docs/plans/2026-08-11-camels-parfc-transition-path-mechanism10-amendment-03b-final.md` | `cc34bb7d181b15aa5ddfc43142b6852d7f6d30d75faaf3dd5b1313887fcef733` |
| 实施计划 | `docs/superpowers/plans/2026-08-11-camels-parfc-path-postcollapse-03b.md` | `f26fd56ef300f90992110144bcc707e49cd64853d327653f2d01ede71cdfdbe2` |
| 路径交互实现 | `src/hbv_joint_uncertainty/imm.py` | `12041163f4f8c54d06ed45e4d8e84ef10c3884f95be538596d728ea3d3aab193` |
| 守恒状态映射 | `src/hbv_joint_uncertainty/hbv_state_mapping.py` | `2c8559df9d304856fc610cb2d29b7f61ef198eb0da67e6c919d3ded3278036bb` |
| 预检和转移适配 | `src/hbv_joint_uncertainty/preflight.py` | `65ccef82344c0b73942fb833321becde487d33358630efa802dab12cec6194e4` |
| CAMELS 任务运行器 | `src/camels_switch_confirmation/g2_switch_confirmation.py` | `1841bb18c7c0fa9eb37013a0cbc96235d8f7fdb5613beeaa152a555fabf58477` |
| 二十项注册运行器 | `src/camels_switch_confirmation/run_parameter_path_mechanism.py` | `5653642a4af74b9b5f17308f2a60679981d8936d596969e4576bb2b2b684d245` |
| 独立核验器 | `src/camels_switch_confirmation/verify_parameter_path_mechanism.py` | `6480c402b0bfa9b831713fda2681bc8eb5e0e52359b37cf51125e64ccfe668f1` |

五个登记测试文件也必须全部写入未来配置，不能只登记运行器要求的最少两个测试角色：

| 测试 | SHA-256 |
|---|---|
| `test/test_hbv_joint_uncertainty_imm.py` | `7391fb90e5d703fd6a834b84661bc8ec517b4f0674417403cab4a2ce4a92078f` |
| `test/test_hbv_parameter_state_mapping.py` | `c040c8b7cf3b5045fb83c51324fd2334ed947b008207abaebd0e2c0430695f63` |
| `test/test_camels_switch_confirmation.py` | `2fa32289b33e900aa1164a02f50f3b3cc301069377b18801f8b3b969b8bef281` |
| `test/test_camels_parameter_path_mechanism.py` | `29746474609d98e8fd9b3464337e87b5247933289733dda78af230cfb7b0c1f2` |
| `test/test_camels_parameter_path_mechanism_verifier.py` | `ce4d0aa04af7d95f5d54b50cfcebb6dc0f205ffe5fbd02d584c3e594d2185c30` |

测试证据：

- `G:\wt\camels-rising\tmp\camels_03b_combined_tests_20260811.stdout.log`，SHA-256 `f550d955e13405d608e1a8342ddf1b1faf955f195a0b757b4a5388ade66b7d1b`。
- `G:\wt\camels-rising\tmp\camels_03b_combined_tests_20260811.stderr.log`，0 字节，SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`。

### 3. 固定输入与尚不存在的文件

- 10 任务表：`docs/plans/2026-08-10-camels-parfc-overconfidence-diagnostic-tasks-v02.csv`，SHA-256 `e20f9d7d3b6f9f7f9bf90f4f94550e2cebc80a17a88d7f24ebabb989e33c4048`。
- 参数表：`results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/hbv_lite_cma_rising_local_full.csv`，SHA-256 `577b12fcb8e1a7a7a607995f0011dbda38a199ee68f3636732b80a3356c16be6`。
- 第一阶段预检表：`results/23_camels_switch_confirmation/g1_precheck_v01/g1_precheck.csv`，SHA-256 `3443ba601434dd30b43c3b5e8a9b838fc666cc394077700ddd4d3e7158b3ee73`。
- 原始输入清单：`docs/plans/2026-08-10-camels-parfc-state-interaction-design90-input-manifest-v01.csv`，SHA-256 `e9214738c64ba35800d06d4c6c07d1a3f31e5615cfefc9e1e55ae99ea3b3818b`。
- CAMELS-US 数据入口：`G:\wt\camels-rising\data\camels_us`。
- 尚不存在：`src/camels_switch_confirmation/configs/camels_parfc_transition_path_03b_mechanism10.json`。
- 尚不存在：`docs/plans/2026-08-11-camels-parfc-transition-path-mechanism10-03b-run-manifest-v01.json`。
- 尚不存在：独立第 0 日初始矩清单；其路径和散列必须在任务 7 中确定并冻结。
- 尚不存在：版本 03B 新结果根和新日志；名称不得现在猜测，必须先登记。

旧全仓测试夹具 `results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/hbv_lite_cma_FINAL_pt_v1_warmup_local_full.csv` 仍缺失。本轮没有重新运行依赖它的旧测试；只能声称上述 186 项相关测试通过，不能声称全仓测试通过。

### 4. 关键证据与结果路径

| 证据 | 路径 |
|---|---|
| 旧交接，仅作历史 | `G:\wt\camels-rising\docs\plans\HANDOFF_20260809_CAMELS_NOISE_ONLY_NEXT.md` |
| ND01 531 流域结果 | `G:\wt\camels-rising\results\23_camels_switch_confirmation\g2_switch_confirmation_v01_noise_nd01_design531_q3e8_r1_s01_20260809_local` |
| 过程噪声 01A 证据 | `G:\wt\camels-rising\docs\plans\2026-08-09-camels-process-noise-only-01a-design90-evidence.json` |
| 参数状态交互 01B 证据 | `G:\wt\camels-rising\docs\plans\2026-08-10-camels-parfc-state-interaction-design90-01b-evidence.json` |
| 过度自信诊断 02A 证据 | `G:\wt\camels-rising\docs\plans\2026-08-10-camels-parfc-overconfidence-diagnostic-02a-evidence.json` |
| 版本 03 失败证据 | `G:\wt\camels-rising\docs\plans\2026-08-10-camels-parfc-transition-path-mechanism10-failure-evidence-v01.json` |
| 版本 03A 失败证据 | `G:\wt\camels-rising\docs\plans\2026-08-11-camels-parfc-transition-path-mechanism10-03a-failure-evidence-v01.json` |
| 版本 03 旧结果根 | `G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_transition_path_03_mechanism10_s01_20260810_local` |
| 版本 03A 旧结果根 | `G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_transition_path_03a_mechanism10_s01_20260810_local` |

版本 03 结果集合 SHA-256 为 `495184901b82fb3ce8dad8d8b490b4831f599142ea9dbcf93429ee07f780b85b`；版本 03A 为 `bfcfc14f178369e46d1cb934191b91d16f548465ec931690b525a91b93e01309`。两者当前均与失败证据登记值一致；旧运行清单中的 `registered_not_run` 状态已经失效，实际状态以失败证据和各自 `runner_summary.json` 为准。

## 六、已确认、已排除和仍未知

### 1. 已确认

1. 原始参数实验把三个候选放入三个独立参数组，实际没有跨参数状态混合；只有候选概率转移。
2. 降低土壤最大蓄水容量时，超额土壤水必须守恒转入上层地下水；旧直接投影会丢水。守恒映射和完整交互使事件通过数和多类别概率误差在探索样本中数值上改善。
3. 在过度自信诊断选取的 10 个失败任务中，观测前把高容量赢家的历史状态压入低容量目标，会反复制造虚假上层地下水和高流量预测，形成后验锁定。
4. 版本 03 和 03A 的中止来自数学等价公式在双精度下的不同累加顺序，不是概率、权重轴或水文路径错误。
5. 三目标逐级合成是唯一主全局后验；九路径直接合成只允许作非阻断诊断。

### 2. 已排除

1. ND01 失败不是任务崩溃、真值变化、非有限概率或概率不归一造成的。
2. 02A 的严重过度自信不是创新方差项主导，因而当前没有证据支持先调过程噪声、观测噪声或似然温度。
3. 版本 03、03A 没有产生改进方法结果，不能用于判断路径方法成功或失败。
4. 186 项测试和内存诊断只能证明实现与数值合同可运行，不能证明科学效果。

### 3. 仍未知

- 版本 03B 是否减少严重错误天数或平均真实候选负对数概率：**未验证**。
- 土壤最大蓄水容量切换是否能稳定辨认：**未验证**。
- 其他参数、完整状态精度、预报价值、真实观测同化价值和参数—噪声联合辨认：**未验证**。
- 当前过程噪声单独切换设计中的概率质量改善没有转化为稳定事件辨认；重新设计后能否达到：**未验证**。

## 七、未完成事项和最高优先下一步

当前阻塞不是代码错误，而是版本 03B 的正式证据链尚未创建，且用户尚未给出创建配置或运行 20 项任务的独立 GO。

最高优先步骤是实施计划的任务 7，不是直接运行：

1. 在用户明确 GO 后创建独立第 0 日初始矩清单，登记 10 个流域—种子任务的初始概率、三个候选十五状态和 15×15 协方差及轴元数据。
2. 创建 `camels_parfc_transition_path_03b_mechanism10.json`，登记最终预注册、全部实现、五个相关测试、Python 可执行文件、输入、旧失败证据和初始矩清单的 SHA-256。
3. 创建版本 03B 运行清单，冻结配置自身 SHA、新输出根、新日志名和两条逐字命令；确认所有目标均不存在且与旧证据隔离。
4. 两名独立审查者只对 20 项任务给出 GO。
5. 再获得单独运行 GO 后，重新运行基线和改进方法各 10 项，并执行独立核验。

若版本 03B 技术门失败，最终 HOLD，不再修订；若技术门通过但任一科学继续门失败，同样 HOLD。只有两项科学继续门都通过，才可申请准备 90 流域设计配置。

## 八、新对话开始后的首查命令

```powershell
$repo = 'G:\wt\camels-rising'
Set-Location $repo

Get-Content -Raw 'G:\wt\camels-rising\docs\plans\HANDOFF_20260811_CAMELS_PARFC_PATH_03B_PREFLIGHT.md'
git status --porcelain
git rev-parse HEAD
git branch --show-current

Get-FileHash -Algorithm SHA256 `
  'docs\plans\2026-08-11-camels-parfc-transition-path-mechanism10-amendment-03b-final.md', `
  'docs\superpowers\plans\2026-08-11-camels-parfc-path-postcollapse-03b.md', `
  'src\hbv_joint_uncertainty\imm.py', `
  'src\hbv_joint_uncertainty\hbv_state_mapping.py', `
  'src\hbv_joint_uncertainty\preflight.py', `
  'src\camels_switch_confirmation\g2_switch_confirmation.py', `
  'src\camels_switch_confirmation\run_parameter_path_mechanism.py', `
  'src\camels_switch_confirmation\verify_parameter_path_mechanism.py'

Test-Path 'src\camels_switch_confirmation\configs\camels_parfc_transition_path_03b_mechanism10.json'
Test-Path 'docs\plans\2026-08-11-camels-parfc-transition-path-mechanism10-03b-run-manifest-v01.json'

Get-CimInstance Win32_Process | Where-Object {
  $_.Name -match '^python' -and
  $_.CommandLine -match 'run_parameter_path_mechanism|camels_parfc_transition_path_03b'
} | Select-Object ProcessId, CommandLine

$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q `
  test\test_hbv_joint_uncertainty_imm.py `
  test\test_hbv_parameter_state_mapping.py `
  test\test_camels_switch_confirmation.py `
  test\test_camels_parameter_path_mechanism.py `
  test\test_camels_parameter_path_mechanism_verifier.py

git diff --check
```

预期：提交 `61e938b3a89f648e460a20e6f03e005bdc9fca4a`；分支 `codex/camels-rising-half-recal`；版本 03B 配置和运行清单均为 `False`；无对应进程；相关测试 `186 passed, 1 warning`；差异格式检查退出码 0。任何不一致都先报告并停止。

未来配置冻结后，运行器和核验器的命令接口分别为：

```powershell
& 'C:\Users\yiqun\anaconda3\python.exe' -m camels_switch_confirmation.run_parameter_path_mechanism `
  --config 'src\camels_switch_confirmation\configs\camels_parfc_transition_path_03b_mechanism10.json' `
  --expected-config-sha256 '<冻结后的配置SHA-256>' `
  --workers 4

& 'C:\Users\yiqun\anaconda3\python.exe' -m camels_switch_confirmation.verify_parameter_path_mechanism `
  --config 'src\camels_switch_confirmation\configs\camels_parfc_transition_path_03b_mechanism10.json' `
  --expected-config-sha256 '<同一冻结配置SHA-256>'
```

以上只是接口模板。配置、日志和输出尚未冻结，当前不得执行。

## 九、可直接粘贴到新对话的下一轮任务提示词

```text
对话名：CAMELS 土壤最大蓄水容量九路径机制 03B / 配置冻结前

项目归属 imm-save。唯一可写代码位置是 G:\wt\camels-rising，主仓库 G:\github\pycharm\projects\neuralhydrology 一律只读；不得清理当前脏工作树、修改旧证据、提交、推送或删除结果。

开始时完整读取：
G:\wt\camels-rising\docs\plans\HANDOFF_20260811_CAMELS_PARFC_PATH_03B_PREFLIGHT.md

随后执行该文件第八节的首查命令，只报告与登记状态的差异。预期为：分支 codex/camels-rising-half-recal，提交 61e938b3a89f648e460a20e6f03e005bdc9fca4a；版本03B配置和运行清单不存在；无对应Python进程；五个相关测试文件合计186项通过。

当前科学状态：完整状态交互和守恒容量映射使事件通过数与Brier分数在数值上改善，但90流域设计中出现严重过度自信，正式门仍失败。新的九路径观测后合并方法只有代码、测试和内存技术预检，尚无正式实验结果。版本03和03A均在科学汇总前因过严的纯绝对差容差门停止，不能解释为方法失败或成功。

本轮先只做只读首查并给出实施计划任务7的可执行清单。未经我在新对话中明确GO，不得创建独立初始矩清单、版本03B配置或运行清单，不得启动20项任务。即使获得创建配置GO，也必须先冻结所有散列、全新输出和日志，并由两名独立审查者通过；实际20项运行仍需单独GO。

只允许设计种子0、1；禁止种子2、3、90或531流域运行和版本02冻结。参数候选辨认、噪声候选辨认、完整状态精度、预报价值和真实观测同化价值必须分开。

回答用中文，结论先行，使用完整通俗名称，明确区分事实、推断和未验证；删除过程性叙述，每次回复以“## 结论”结束。
```
