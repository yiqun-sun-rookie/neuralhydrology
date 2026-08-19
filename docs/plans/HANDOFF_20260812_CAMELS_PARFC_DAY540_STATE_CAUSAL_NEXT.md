# 交接：土壤最大蓄水容量九路径方法——第540天完整状态因果诊断后（2026-08-12）

**当前结论：需要重置上下文。九路径观测后合并方法在九十流域、设计种子0和1的技术核验通过，但预登记科学门仍为暂停。单流域真实完整状态反事实证明，错误完整状态是第540—719天概率崩塌的因果触发因素之一；它没有形成可运行修复，因为失败转移到第720天且六次切换仍只通过三次。当前唯一优先下一步是使用已有数组只读分解第360—539天各状态误差的形成过程，不扩大流域、不更换概率分布、不启动新实验。**

## 一、整体目标与当前阶段

本线属于论文项目 `imm-save`；论文项目目录为 `G:\github\pycharm\projects\paper-imm-variable-params`。最终目标是判断交互多模型状态更新方法能否在参数和噪声均不确定时，可靠辨认候选制度，并进一步提供准确的完整水文状态和有价值的流量预报。

当前 CAMELS-US 线仍使用真实流域率定参数和真实气象强迫，但径流与状态真值由同一简化概念性降雨—径流模型合成。当前证据只涉及**土壤最大蓄水容量候选辨认及其失败机制**；它不是完整状态精度、预报价值或真实观测同化证据。

当前阶段已从“九路径方法是否总体优于完整状态交互”转为“为什么流域07184000、设计种子0在第540天前已经形成错误且过度自信的完整状态”。该局部机制必须先解释，才有理由设计可运行修复或增加流域。

## 二、已完成单因素反事实的固定合同

- 对象：CAMELS-US 流域 `07184000`，设计种子 `0`，1260个模拟日。
- 方法：九条“昨日来源候选到今日目标候选”路径分别观测，观测后合并为三个目标候选，再合成唯一的十五状态全局后验。
- 候选：率定中心土壤最大蓄水容量、中心值的一半、中心值的两倍；其他十二个参数相同。
- 真实顺序：中心→一半→两倍→中心→两倍→一半→中心，每段180天。
- 概率证据：原始高斯分布；未使用学生 t 分布、概率下限、协方差膨胀或对数概率递归替代。
- 唯一变化：第540天观测更新前，把当时概率为1的“两倍容量”来源候选的十五状态均值一次性替换为同一时刻的合成真实状态。
- 保持不变：候选概率、候选协方差、全局状态与协方差、参数、气象强迫、观测、转移矩阵、状态映射、过程协方差、观测方差和后续算法。
- 性质：这是使用已知合成真值的因果诊断，不是现实中可运行的方法。

下一阶段尚未冻结新实验合同，也未获得新运行授权。现阶段只允许读取现有十五状态轨迹，分解第360—539天误差何时、在哪些状态中形成。

## 三、权限、成功标准和停止条件

### 权限边界

- 唯一可写代码工作树：`G:\wt\camels-rising`。
- 主仓库 `G:\github\pycharm\projects\neuralhydrology` 一律只读。
- 保留当前脏工作树和全部旧证据；不得清理、提交、推送、删除、移动、覆盖或改写已有结果。
- 只允许设计种子 `0`、`1`。种子 `2`、`3` 禁止使用。
- 未经新的明确授权，不得启动新的单任务反事实、二十项机制检查、九十流域或五百三十一流域运行，也不得冻结版本02。
- 参数候选辨认、噪声候选辨认、完整状态精度、预报价值和真实观测同化价值必须分别判断。
- 安全的只读核对命令可自主执行；这不扩大实验授权。

### 当前阶段的可验证成功标准

只读误差分解应能够逐日、逐状态报告：原始误差、用候选协方差标准化后的误差、首次明显偏离的时间和第540天误差排名。该分析只能确定后续因果干预的优先状态或预先定义的状态组，不能单独证明因果。

如果随后拟做状态分量替换实验，必须另获明确授权，并一次只替换一个预先定义的状态或状态组。其局部判据应同时检查第540—719天是否恢复、以及失败是否再次转移到第720—899天；六次事件总通过数不得省略。

### 强制停止

- 冻结结果集合指纹、来源任务散列、分支、提交或输入身份与本文件不符时，立即暂停并只报告差异。
- 真值重放不能与冻结流量逐位一致，或第0—539天重放不能与冻结来源轨迹逐位一致时，不得解释新结果。
- 输出目录或日志已存在、位于冻结结果根内，或需要修改旧证据时，不得运行。
- 技术核验失败时不得计算科学效果；技术核验通过也不得写成科学效果通过。
- 当前只读分解完成后停止；任何新写入、新配置或运行均需用户再次明确授权。

## 四、已完成方案、关键结果和失败结论

### 1. 九十流域九路径观测后合并设计：技术通过，科学暂停

事实：九十个流域、设计种子0和1、完整状态交互方法与九路径观测后合并方法共360项任务全部完成，独立核验状态为 `passed`。评分日为每种方法194400天。

| 指标 | 完整状态交互方法 | 九路径观测后合并方法 |
|---|---:|---:|
| 通过切换事件 | 706/1080 | 717/1080 |
| 事件通过率 | 0.653704 | 0.663889 |
| 多类别布赖尔分数 | 0.357974 | 0.335411 |
| 平均真实候选负对数概率 | 9543.506548 | 653.483250 |
| 真实候选普通概率为零的日数 | 2044 | 814 |
| 真实候选概率低于0.01的日数 | 7546 | 5598 |
| 真实候选负对数概率大于100的日数 | 2805 | 1514 |

事实：九路径方法的“一半容量→中心容量”通过率为 `57/180=0.316667`，“中心容量→两倍容量”为 `75/180=0.416667`，“一半容量→两倍容量”为 `87/180=0.483333`，均低于登记下限0.5；它还有814个零概率日、1514个严重日，平均负对数概率也高于登记上限 `log(3)=1.098612`。总科学判定为 `HOLD`。

结论：九路径方法数值上改善了事件数、布赖尔分数和概率尾部，但没有实现稳定候选辨认，不能扩展或称为科学成功。

### 2. 自由度为1的学生 t 分布概率证据：消除零概率，不是解法

事实：只在流域07184000、设计种子0上，从第0天公平在线重跑两种方法；两者都把原创新协方差解释为学生 t 分布的尺度矩阵，自由度为1，内部状态修正仍使用原高斯公式。这不是保持相同方差的比较。

| 区间 | 完整状态交互方法 | 九路径观测后合并方法 |
|---|---:|---:|
| 第540—719天平均真实候选概率 | 0.671386 | 0.651622 |
| 第540—719天多类别布赖尔分数 | 0.314889 | 0.353334 |
| 第540天事件响应 | 11天，通过 | 19天，通过 |
| 第720—899天平均真实候选概率 | 0.627967 | 0.518917 |
| 第720—899天多类别布赖尔分数 | 0.560392 | 0.668079 |
| 六次切换通过数 | 3/6 | 3/6 |

事实：两种方法的零概率日均为0，但第720天事件均未通过；同一概率证据下完整状态交互在两个重点区间都优于九路径方法。

结论：重尾概率证据只说明原高斯尾部惩罚和普通浮点下溢会放大失败；它没有使九路径方法成立，也没有形成跨流域证据。当前不得增加流域测试该路线。

### 3. 第540天十五状态真实值替换：局部因果触发得到支持，整体修复失败

事实：干预前“两倍容量”来源候选概率为1，真实“中心容量”来源概率仅 `5.87641573e-26`。该来源候选的土壤水为 `398.739843` 毫米，真实值为 `245.139173` 毫米，偏高 `153.600670` 毫米，即其协方差标准差的 `58.1555` 倍；下层地下水为 `3359.361406` 毫米，真实值为 `3554.445611` 毫米，偏低 `195.084205` 毫米，即 `6.72987` 个标准差。替换时概率、协方差、全局状态和全局协方差均逐位未变。

| 指标 | 原始高斯九路径 | 仅替换十五状态均值 |
|---|---:|---:|
| 第540天事件 | 不通过 | 10天响应，通过 |
| 第540—719天零概率日 | 156 | 0 |
| 第540—719天平均真实候选概率 | 1.9283e-27 | 0.661337 |
| 第540—719天多类别布赖尔分数 | 2.000000 | 0.426080 |
| 第719天真实候选概率 | 0 | 0.020755 |
| 第720天事件 | 0天响应，通过 | 不通过 |
| 第720—899天平均真实候选概率 | 1.000000 | 0.572741 |
| 第720—899天多类别布赖尔分数 | 0 | 0.694718 |
| 六次切换通过数 | 3/6 | 3/6 |

推断：错误完整来源状态是第540—719天灾难性概率锁定的因果触发因素之一；保持原守恒容量映射不变仍能在替换真实状态后恢复该段，因而“映射实现公式本身错误”不是该段失败的充分解释。

限制：一次替换了全部十五个状态，尚不能确定土壤水、下层地下水或十个径流路由记忆状态中哪些是必要因素。失败转移到下一阶段，说明一次真实状态重置不是整体方法。

### 4. 版本03和03A：只有数值技术失败，没有科学结果

- 版本03：计划20项，提交14项；完整状态交互10项成功，九路径4项失败，6项未提交。首次失败为流域07145700、种子1、第39天，数学等价的两种合成顺序状态差 `1.8189894035458565e-12`，相对尺度 `8.1931e-16`。
- 版本03A：计划20项，提交12项；完整状态交互10项成功，九路径2项失败，8项未提交。流域07145700、种子0、第435天协方差差 `1.6370904631912708e-11`、相对差 `4.3998e-15`；80位小数重算差仅 `3.4e-75`。流域05501000、种子1、第1194天状态差 `1.3642420526593924e-12`、相对差 `5.5277e-16`。

结论：两次都在科学汇总前被过严的纯绝对浮点容差停止，不能解释为方法成功或失败；旧输出不得修改或拼接。

## 五、当前代码、配置、输入、日志和证据

以下散列均为2026-08-12现场计算的安全散列算法256位值。

### 1. 九十流域冻结合同与来源

| 用途 | 完整路径 | 安全散列算法256位值 |
|---|---|---|
| 冻结配置 | `G:\wt\camels-rising\src\camels_switch_confirmation\configs\camels_parfc_transition_path_03b_design90.json` | `b7bd90e752738b4a9d766e0138e7d9007f97c18443cc7764e0bba6d0b5221669` |
| 任务表 | `G:\wt\camels-rising\docs\plans\2026-08-11-camels-parfc-transition-path-03b-design90-tasks-v01.csv` | `add9f3444ff2d4069a1fd8c4fb99056dd91f932ef3fe53b523b6644fc43cf95e` |
| 十五状态初始矩清单 | `G:\wt\camels-rising\docs\plans\2026-08-11-camels-parfc-transition-path-03b-design90-initial-moment-manifest-v01.npz` | `3d12d5c289edeb477ae285a914e456643bc1b581ed603a1f4cd73aa998ce7042` |
| 运行清单 | `G:\wt\camels-rising\docs\plans\2026-08-11-camels-parfc-transition-path-03b-design90-run-manifest-v01.json` | `930e803169b028eb43c78f34b1e19bacd17dacb88372b7bf0dbbf6b6aec7a442` |
| 运行前证据 | `G:\wt\camels-rising\docs\plans\2026-08-11-camels-parfc-transition-path-03b-design90-preflight-evidence-v01.json` | `95bc2e7ebd56871a29f85b9480d36f75a8a647ce9737a04cd94bf69d1a4eb387` |
| 原始输入清单 | `G:\wt\camels-rising\docs\plans\2026-08-10-camels-parfc-state-interaction-design90-input-manifest-v01.csv` | `e9214738c64ba35800d06d4c6c07d1a3f31e5615cfefc9e1e55ae99ea3b3818b` |
| 参数表 | `G:\wt\camels-rising\results\10_global_conceptual_model_benchmark\camels_us_531_repro_v01\summary\hbv_lite_cma_rising_local_full.csv` | `577b12fcb8e1a7a7a607995f0011dbda38a199ee68f3636732b80a3356c16be6` |
| 第一阶段预检表 | `G:\wt\camels-rising\results\23_camels_switch_confirmation\g1_precheck_v01\g1_precheck.csv` | `3443ba601434dd30b43c3b5e8a9b838fc666cc394077700ddd4d3e7158b3ee73` |

冻结结果根：`G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_transition_path_03b_design90_s01_20260811_local`。现场重算得到368个文件、4183981094字节，集合指纹为 `57d8fef9037c29d0a68f915d5337f3be7bfab2224ebada575be6161e070126e6`。

独立核验汇总：`G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_transition_path_03b_design90_s01_20260811_local\verification\verification_summary.json`，安全散列算法256位值 `3473491b3141a404df4f9797f270cbd5d749bb3b22aa6d43e1326f884b0f7b46`。

注意：冻结运行清单仍保留“登记、未运行、等待单独授权”的运行前状态；用户随后已授权并产生上述冻结结果。该文字差异是证据时序，不得回写旧清单；当前执行状态以结果根和独立核验汇总为准。

### 2. 第540天反事实

- 实施计划：`G:\wt\camels-rising\docs\superpowers\plans\2026-08-12-camels-parfc-07184000-day540-truth-state-counterfactual.md`，散列 `7d978b0973be64dcd8f77c68101ef49edb7b559bf6fd74cff49a298b6dde5e87`。
- 运行器：`G:\wt\camels-rising\src\camels_switch_confirmation\run_day540_truth_state_counterfactual.py`，散列 `de164119555c55d6a22f7c4f0fe9ffec039c12bdd3923c5d3c9e07a3e2a56266`。
- 测试：`G:\wt\camels-rising\test\test_camels_day540_truth_state_counterfactual.py`，散列 `44db8170ea1ce083ecb825e1f9d4f77293280dc074c2e7ac5276236ef30ac2ec`。
- 冻结来源任务：`G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_transition_path_03b_design90_s01_20260811_local\arms\P\probs\07184000_s0.npz`，散列 `8b9a6766e7c2c5b5bba344dbf2033fbff55dacb31ff3de51383f542b23c00beb`。
- 结果根：`G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_20260812_local`。
- `counterfactual.npz`：`8d4b324baedee308b1916a8d2fd188c20478e925bb72fe56fa3d6e6957b38afe`。
- `run_contract.json`：`6710eaf38d089c4026dab87f7e7884fcdcfe8fbac51fcaa52fd53c026a81cf34`。
- `summary.json`：`b2e831e1fa4d0574869fc4b5cd69d2798de21c54e59801bb25bab2acb48f31f8`。
- `verification.json`：`7a6216c81564ffacdc8b1853f177cbaf66e7a9be3b089d52bcc19d4db30741e3`，状态 `PASS`。
- 运行标准输出日志：`G:\wt\camels-rising\tmp\camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_run.stdout.log`，散列 `82d10e84367fe6896fbc5c1d6113c0f71bd04b8825db423c4c0337756dc86b5d`。
- 重载核验标准输出日志：`G:\wt\camels-rising\tmp\camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_verify.stdout.log`，散列 `3b13929290445d886dca40e1d400f124f4ec8d8222195f07dbd461027e1401b8`。
- 两个对应标准错误日志均为0字节，散列均为 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`。

### 3. 学生 t 分布单流域公平诊断

- 结果根：`G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_model_evidence_fair_07184000_s0_01_20260811_local`。
- `arms\C\07184000_s0.npz`：`888f31ca173a1c25eb738994af384e460b85e6e190f672c832c6b4ed80a527fd`。
- `arms\P\07184000_s0.npz`：`08f9838889448f53a8953887a6156fffbf044ec3ce28d4002f947ccc2fe31ce9`。
- `run_contract.json`：`cfbf856519ccab77718ae6b9e814b48e8ff8b2a461398b5d145d1e7d2d3d6975`。
- `summary.json`：`3f3e3b7d032e62fc5b24629e821e247e298f720837f5d730072090685357b6ea`。
- `verification.json`：`1af6f30cf8be4f1e5b008802772953f3b3c6b529180ee80a297506a05bb82ced`，状态 `PASS`。
- 权威重载核验日志：`G:\wt\camels-rising\tmp\camels_parfc_model_evidence_fair_07184000_s0_01_verify_v02.stdout.log`，散列 `4c98849d4bad7667052ffc3b11732c76b724790f05b099de10d2685321f61ac1`；对应标准错误日志为0字节。
- 较早的无版本后缀核验日志记录一次已被修正的核验尝试，不是权威结果，必须保留但不得引用为最终状态。
- 概率对比图：`C:\Users\yiqun\.codex\visualizations\2026\08\11\019feee1-e311-7f83-be48-b3e643cfb14c\camels_07184000_student_t_fair_probability_comparison.png`，散列 `7e865f5584e3513e145de9298e81173b29e9a8654b5181ae8ffaa55278fefeb6`。

### 4. 关键当前实现散列

| 文件 | 安全散列算法256位值 |
|---|---|
| `G:\wt\camels-rising\src\hbv_joint_uncertainty\imm.py` | `b56b0b1b128c0c0cfb1bda6cfacd5c7fe7ac8a91af5c0aaad5d198944211737c` |
| `G:\wt\camels-rising\src\hbv_joint_uncertainty\hbv_state_mapping.py` | `2c8559df9d304856fc610cb2d29b7f61ef198eb0da67e6c919d3ded3278036bb` |
| `G:\wt\camels-rising\src\hbv_joint_uncertainty\preflight.py` | `65ccef82344c0b73942fb833321becde487d33358630efa802dab12cec6194e4` |
| `G:\wt\camels-rising\src\camels_switch_confirmation\g2_switch_confirmation.py` | `437f703745f883af3886d202244e7899c8bf5a68ce2cb76f7f652cb9230b9f89` |
| `G:\wt\camels-rising\src\camels_switch_confirmation\run_parameter_path_design90.py` | `9b5023eec8f6b627ba78ed7662b523ad0be5f5613c1cea6b7740b53a57583482` |
| `G:\wt\camels-rising\src\camels_switch_confirmation\verify_parameter_path_design90.py` | `252af118d2c60d9885f5568a7ad64a7e8bd207cdfb8e4d221fa7bd54b6486f8e` |
| `G:\wt\camels-rising\src\camels_switch_confirmation\run_student_t_fair_single_task.py` | `6137bb8c308b6fe02b36c8ee0bddde0af254adcabd86fda96aa6fc8f62119531` |

### 5. 版本03和03A停止证据

- 版本03失败证据：`G:\wt\camels-rising\docs\plans\2026-08-10-camels-parfc-transition-path-mechanism10-failure-evidence-v01.json`，散列 `4ecf017a5ef5625250568a939ef37851e02b1f5d015ad3011872f1cdcca9c316`。旧输出根为 `G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_transition_path_03_mechanism10_s01_20260810_local`；现场重算为13个文件、895677字节，集合指纹 `495184901b82fb3ce8dad8d8b490b4831f599142ea9dbcf93429ee07f780b85b`。
- 版本03A失败证据：`G:\wt\camels-rising\docs\plans\2026-08-11-camels-parfc-transition-path-mechanism10-03a-failure-evidence-v01.json`，散列 `ae1cbe00a2091926edc5ac4500fe7f4ce1788a9fac3832e8830f8eed706c4344`。旧输出根为 `G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_transition_path_03a_mechanism10_s01_20260810_local`；现场重算为13个文件、896011字节，集合指纹 `bfcfc14f178369e46d1cb934191b91d16f548465ec931690b525a91b93e01309`。

现场无缓存测试命令覆盖当前九十流域合同、学生 t 分布诊断和第540天反事实的七个测试文件，结果为 `127 passed, 1 warning in 1.19s`。警告仅为仓库既有的未知 `collect_ignore_glob` 配置项；本次现场测试没有新增持久日志。

## 六、已确认、已排除和未验证

### 事实

- 九路径方法在九十流域的技术重建与高精度合成检查通过，但科学门失败。
- 流域07184000、种子0的第540天前来源状态已与合成真值相差数十个自身标准差；只替换十五状态均值能解除该段零概率锁定。
- 学生 t 分布概率证据能消除该单任务的零概率，但未增加六次切换总通过数，且同条件下完整状态交互更好。
- 第540天全部十五状态替换把失败移到第720天，未消除整体失败。

### 推断

- 错误完整状态与过窄候选协方差共同造成过度自信；普通浮点下溢是锁定的放大器，不是唯一根因。
- 守恒容量映射在传播已有错误状态，而不是已证明存在代数实现错误。

### 未验证

- 十五个状态中哪些是第540天恢复的必要或充分因素。
- 状态误差在第360—539天何时产生，以及来自滤波修正、候选合并、过程协方差还是结构失配。
- 任一可运行的状态修复、协方差修复或稳健概率方法。
- 跨流域一般性、保留种子验证、完整状态精度、预报价值、噪声候选辨认和真实观测同化价值。

## 七、工作树、分支、提交、进程和冻结状态

- 工作树：`G:\wt\camels-rising`。
- 分支：`codex/camels-rising-half-recal`。
- 提交：`61e938b3a89f648e460a20e6f03e005bdc9fca4a`。
- 当前状态：124个简短状态条目，其中4个已跟踪修改、120个未跟踪条目；本交接文件是新增的第120个未跟踪条目。
- 已跟踪修改：`src/camels_switch_confirmation/g2_switch_confirmation.py`、`src/hbv_joint_uncertainty/imm.py`、`src/hbv_joint_uncertainty/preflight.py`、`test/test_hbv_joint_uncertainty_imm.py`。
- 与当前诊断直接相关的未跟踪代码和测试包括：`run_day540_truth_state_counterfactual.py`、`run_student_t_fair_single_task.py`、`test_camels_day540_truth_state_counterfactual.py`、`test_camels_student_t_fair_single_task.py`，以及九十流域配置、注册、运行和核验文件。其余历史未跟踪证据也必须保留。
- `git diff --check` 通过；没有提交、暂存或推送。
- 当前相关 Python 进程：0。
- Python：`C:\Users\yiqun\anaconda3\python.exe`，散列 `c98caee82c66433f0e89d4abbf152b39a7dc2e99979b28dcb021598b4e3f5642`；版本3.11.5，NumPy 1.26.4。
- 九十流域版本03B配置、任务表、十五状态初始矩清单、运行清单和结果均已冻结并执行；科学状态为暂停。
- 当前误差分解没有新配置、运行清单、输出目录或运行进程。

## 八、未完成事项、阻塞与唯一优先下一步

阻塞不是任务数量不足，而是因果归因不足：全部十五状态同时替换只证明“完整状态整体”参与了第540天失败，不能告诉我们应修哪个状态或哪一步算法。此时增加流域只会重复一个尚未定义的机制问题。

唯一优先下一步：只读使用反事实结果中的 `truth_source_states`、`source_states` 和 `source_covariances`，分析第360—539天“两倍容量”来源候选的十五个状态误差轨迹。先按五个水文蓄量状态和十个径流路由记忆状态报告，再单列土壤水与下层地下水；输出原始误差、标准化误差、误差峰值日和第540天排名。

完成该只读归因后停止，并给出一个最小、单因素、可证伪的后续干预建议。未经用户明确授权，不创建脚本、配置、图、结果或日志，不运行新的反事实。

## 九、新任务的首读文件和只读命令

### 首先完整读取

1. `G:\wt\camels-rising\docs\plans\HANDOFF_20260812_CAMELS_PARFC_DAY540_STATE_CAUSAL_NEXT.md`
2. `G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_20260812_local\run_contract.json`
3. `G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_20260812_local\summary.json`
4. `G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_20260812_local\verification.json`
5. `G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_transition_path_03b_design90_s01_20260811_local\verification\verification_summary.json`

### 首查命令

```powershell
Set-Location -LiteralPath 'G:\wt\camels-rising'
Get-Content -LiteralPath 'docs\plans\HANDOFF_20260812_CAMELS_PARFC_DAY540_STATE_CAUSAL_NEXT.md' -Raw
git branch --show-current
git rev-parse HEAD
git status --short --branch
git diff --check
```

```powershell
Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^(python|pythonw|pytest)(\.exe)?$' -and
    $_.CommandLine -match 'camels|parfc|day540|student_t|parameter_path'
} | Select-Object ProcessId, Name, CommandLine
```

预期：分支与提交如第七节所列，只有本文件造成的状态条目增量，无匹配 Python 进程。只报告差异。

```powershell
$env:PYTHONPATH = 'G:\wt\camels-rising\src'
& 'C:\Users\yiqun\anaconda3\python.exe' -c "from pathlib import Path; from camels_switch_confirmation.register_parameter_path_design90 import collection_fingerprint; f=collection_fingerprint(Path(r'G:\wt\camels-rising\results\23_camels_switch_confirmation\camels_parfc_transition_path_03b_design90_s01_20260811_local')); print(f['count']); print(f['bytes']); print(f['sha256_of_newline_joined_sorted_entries'])"
```

预期依次为 `368`、`4183981094`、`57d8fef9037c29d0a68f915d5337f3be7bfab2224ebada575be6161e070126e6`。

```powershell
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q -p no:cacheprovider test/test_camels_day540_truth_state_counterfactual.py test/test_camels_student_t_fair_single_task.py test/test_camels_parameter_path_design90.py test/test_camels_parameter_path_design90_registration.py test/test_camels_parameter_path_design90_verifier.py test/test_hbv_joint_uncertainty_imm.py test/test_camels_switch_confirmation.py
```

当前预期为 `127 passed, 1 warning`。该测试只证明当前实现和审计合同未漂移，不证明科学有效。

## 十、新任务回答规则

- 中文，结论先行；使用完整通俗名称。
- 明确分开事实、推断和未验证内容。
- 删除过程性叙述，只报告决定性证据、差异、边界和下一步。
- 每次回复以“## 结论”结束。
