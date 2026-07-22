# 十五状态候选观测似然可辨识性诊断实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在不调用状态交互和候选权重转移的条件下，保存并确认三个切换场景中真实候选的逐日与累计观测对数似然可辨识性。

**Architecture:** 新增一个纯诊断模块，复用冻结候选构建与独立真值生成，但直接逐个调用候选滤波器，不调用交互式多模型滤波器的步骤函数。新增不可覆盖的实验运行器，分别封存开发和确认配置、原始数组、复算表、资源记录、源码快照与保护文件校验值。

**Tech Stack:** Python、NumPy、pandas、pytest、psutil。

---

### Task 1: 冻结无交互候选似然接口

**Files:**
- Create: `test/test_hbv_candidate_likelihood_identifiability.py`
- Create: `src/hbv_multilead_joint_uncertainty/candidate_likelihood_identifiability.py`

**Step 1: Write the failing test**

编写聚焦测试，要求模块存在、三个场景候选数分别为三、三、九，并通过替换交互式多模型滤波器步骤函数为抛错函数证明诊断没有调用状态交互或候选权重更新。

**Step 2: Run test to verify it fails**

Run: `python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py -q`

Expected: FAIL，因为诊断模块尚不存在。

**Step 3: Write minimal implementation**

实现结果数据类、候选选择、独立候选逐日滤波和最小输入验证；逐日保存预测观测、创新、创新方差和观测对数似然。

**Step 4: Run test to verify it passes**

Run: `python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py -q`

Expected: PASS。

### Task 2: 冻结评分窗口、累计值和严格排名

**Files:**
- Modify: `test/test_hbv_candidate_likelihood_identifiability.py`
- Modify: `src/hbv_multilead_joint_uncertainty/candidate_likelihood_identifiability.py`

**Step 1: Write the failing tests**

使用手工构造的候选对数似然数组验证：每阶段排除前五日、累计值从第六日重置、并列对真实候选不利、首次第一名和首次保持第一名日数、从未第一时为 `-1`。

**Step 2: Run tests to verify they fail**

Run: `python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py -q`

Expected: FAIL，因为评分函数尚不存在。

**Step 3: Write minimal implementation**

实现评分数组构建和严格排名，不引入权重或交互参数。

**Step 4: Run tests to verify they pass**

Run: `python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py -q`

Expected: PASS。

### Task 3: 冻结场景级判定与区块重采样

**Files:**
- Modify: `test/test_hbv_candidate_likelihood_identifiability.py`
- Modify: `src/hbv_multilead_joint_uncertainty/candidate_likelihood_identifiability.py`

**Step 1: Write the failing tests**

构造已知通过和已知不通过数组，验证稳定比例、以区块为单位的 `20000` 次重采样区间、中位累计差、第二和第三阶段共同决定场景结论。

**Step 2: Run tests to verify they fail**

Run: `python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py -q`

Expected: FAIL，因为场景判定尚不存在。

**Step 3: Write minimal implementation**

实现阶段汇总和场景判定，第一阶段只报告不参与最终通过。

**Step 4: Run tests to verify they pass**

Run: `python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py -q`

Expected: PASS。

### Task 4: 建立不可覆盖证据运行器

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_candidate_likelihood_identifiability.py`
- Modify: `test/test_hbv_candidate_likelihood_identifiability.py`

**Step 1: Write the failing test**

用一个区块和缩短阶段运行打包测试，验证运行前登记先于数值计算、输出名等于实验编号、已有目录拒绝覆盖、输出与保护路径不重叠、原始数组和四类表存在、配置及源码快照校验值可复算。

**Step 2: Run test to verify it fails**

Run: `python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py -q`

Expected: FAIL，因为运行器尚不存在。

**Step 3: Write minimal implementation**

实现配置加载、动态资源估计、运行前登记、原子输出、原始数组、表格、环境记录、源码快照、保护文件前后校验和目录校验值。

**Step 4: Run test to verify it passes**

Run: `python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py -q`

Expected: PASS。

### Task 5: 创建并运行开发区块

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_*_development_v01.json`
- Create: `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_*_development_v01/`

**Step 1: Freeze three development configs**

三个配置各使用十二个相同开发区块，种子与第二版正式区块及计划中的确认区块不相交；登记三类候选、十个评分日和冻结判定规则。

**Step 2: Estimate resources from actual shapes or a one-block pilot**

记录数组字节数、代表性峰值驻留内存增长、当前可用物理与提交内存、安全余量和预计串行运行时间；余量不足时减少同时存在的场景结果，不减少科学区块数。

**Step 3: Run each development experiment once**

Run: `python src/hbv_multilead_joint_uncertainty/scripts/run_candidate_likelihood_identifiability.py --repo-root <repo> --config <config> --output-dir <new-output>`

Expected: 每个新目录完整封存且完整性门通过。

**Step 4: Review development evidence**

只使用开发区块确认实现、数据字段、资源规模和判定规则可执行，不读取第二版八个正式区块选择设置。

### Task 6: 冻结并运行独立确认区块

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_*_confirmation_v01.json`
- Create: `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_*_confirmation_v01/`

**Step 1: Freeze confirmation configs before reading confirmation outcomes**

确认配置复制已明确的开发设置，仅更换为十二个全新确认区块并记录配置安全散列算法校验值。

**Step 2: Run each confirmation experiment once**

使用同一运行器单进程串行运行三个确认场景；禁止依据结果修改配置或重跑同一区块。

**Step 3: Verify immutable evidence**

重新计算配置、源码快照、输出清单和保护路径校验值；任何不一致均使科学判断无效。

### Task 7: 两层独立核验与阶段结论

**Files:**
- Create: `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_identifiability_synthesis_v01/independent_method_and_result_review.md`
- Create: `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_identifiability_synthesis_v01/independent_raw_evidence_verification.md`
- Create: `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_identifiability_synthesis_v01/final_synthesis.md`

**Step 1: Independent method and result review**

独立上下文逐项审查代码、无交互边界、候选与真值对应、开发—确认隔离、判定规则和结果解释；发现问题后修复并重新审查，但不得重选确认设置。

**Step 2: Independent raw evidence verification**

另一个独立上下文不读取汇总结论，从原始观测、预测观测、创新方差和候选对数似然复算逐日值、累计值、严格排名、首次第一日、稳定比例、重采样区间和最终判断。

**Step 3: Fresh final verification**

Run: `python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py test/test_hbv_three_stage_switching_validation.py test/test_hbv_joint_method_validation.py test/test_hbv_multilead_methods.py test/test_hbv_multilead_forecast.py test/test_hbv_synthetic_truth.py -q`

Expected: 所有测试通过；仅允许已解释的仓库既有测试配置警告。

**Step 4: Write evidence-proportional conclusion**

明确区分开发结果和确认结果；只在两个切换后阶段均通过冻结规则时称为“当前候选观测似然稳定可辨识”，否则称为“在当前条件下未达到稳定可辨识标准”。
