# CAMELS 流域 07184000 第540天真实状态反事实 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在原始高斯九路径方法中，仅于第540天替换占主导来源候选的15状态均值，检验错误完整状态是否是概率崩塌的必要触发因素。

**Architecture:** 从冻结的流域 `07184000`、设计种子 `0` 九路径任务逐位复用强迫、观测、参数候选、初始矩和概率设置；从第0天在线重放，在第540天更新前只替换一个候选的状态均值。新运行器保存反事实结果、唯一干预记录和证据链；核验器重载结果、重建合成真实状态、重跑反事实并核对冻结结果指纹。

**Tech Stack:** Python 3.11、NumPy、pytest、现有 HBV-lite 十五状态模型与九路径观测后合并估计器。

## Global Constraints

- 唯一可写代码位置为 `G:\wt\camels-rising`；不得修改主仓库、旧证据或冻结结果。
- 仅流域 `07184000`、设计种子 `0`、九路径观测后合并方法；不得扩展到其他种子或流域。
- 概率证据保持原始高斯分布；不得同时使用学生 t 分布、概率下限或协方差膨胀。
- 唯一变化是第540天更新前，占主导来源候选的十五状态均值替换为同一时刻的合成真实状态；概率、协方差、参数、转移矩阵、强迫、观测及后续算法不变。
- 输出必须写入不存在的全新目录；拒绝冻结根本身及其任何子目录。
- 该实验是使用合成真值的因果诊断，不是可运行方法、状态精度证据或预报价值证据。
- 不提交、不推送、不删除结果，不清理脏工作树。

---

### Task 1: 冻结反事实合同和失败优先测试

**Files:**
- Create: `src/camels_switch_confirmation/run_day540_truth_state_counterfactual.py`
- Create: `test/test_camels_day540_truth_state_counterfactual.py`

**Interfaces:**
- Consumes: 冻结九路径任务 `07184000_s0.npz`、`_build_bank()`、`advance_state()`。
- Produces: `replay_truth_with_states(source) -> TruthReplay`、`apply_day540_state_intervention(estimator, truth_source_state) -> InterventionRecord`。

- [ ] **Step 1: 写真实状态重放测试**

  构造短序列，要求逐日保存更新前和更新后的十五状态；每个更新后状态必须等于直接调用 `advance_state()` 并施加同一地下水随机扰动的结果。

- [ ] **Step 2: 运行测试并确认因接口不存在而失败**

  Run: `C:\Users\yiqun\anaconda3\python.exe -m pytest -q test/test_camels_day540_truth_state_counterfactual.py`

- [ ] **Step 3: 写单因素干预测试**

  保存干预前所有候选状态、协方差、概率和全局状态；调用干预后只允许指定候选的状态均值变化，且该状态逐位等于真实状态。

- [ ] **Step 4: 实现最小真实状态重放和干预函数**

  真值随机数使用 `SeedSequence((20260807, 7184000, 0))`；干预时刻固定为第540天更新前；来源候选必须是索引2且为唯一最大概率候选。

- [ ] **Step 5: 运行测试并确认通过**

  Run: `C:\Users\yiqun\anaconda3\python.exe -m pytest -q test/test_camels_day540_truth_state_counterfactual.py`

### Task 2: 隔离运行、保存和核验

**Files:**
- Modify: `src/camels_switch_confirmation/run_day540_truth_state_counterfactual.py`
- Modify: `test/test_camels_day540_truth_state_counterfactual.py`

**Interfaces:**
- Consumes: `replay_truth_with_states()`、`apply_day540_state_intervention()`。
- Produces: `run_counterfactual(source_task, frozen_root, output_root) -> dict`、`verify_counterfactual(...) -> dict`。

- [ ] **Step 1: 写输出安全测试**

  要求已有输出根、冻结根及冻结根子目录在任何写入前失败；失败后不得产生新文件。

- [ ] **Step 2: 写在线重放集成测试**

  要求第0—539天的概率、稳定对数概率、来源状态和协方差与冻结任务逐位一致；第540天只记录一次状态均值干预。

- [ ] **Step 3: 实现全新输出合同**

  实验编号固定为 `CAMELS_PARFC_DAY540_TRUTH_STATE_COUNTERFACTUAL_07184000_S0_01`；输出根固定为 `results/23_camels_switch_confirmation/camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_20260812_local`。保存 `run_contract.json`、`counterfactual.npz`、`summary.json` 和 `verification.json`。

- [ ] **Step 4: 实现重载核验**

  重新生成真实状态，核对真值流量与冻结文件逐位一致；重新运行反事实并核对保存概率、状态干预记录和指标；重新计算冻结结果集合指纹并要求等于 `57d8fef9037c29d0a68f915d5337f3be7bfab2224ebada575be6161e070126e6`。

- [ ] **Step 5: 运行相关测试**

  Run: `C:\Users\yiqun\anaconda3\python.exe -m pytest -q test/test_camels_day540_truth_state_counterfactual.py test/test_hbv_joint_uncertainty_imm.py test/test_camels_switch_confirmation.py`

### Task 3: 执行一个反事实任务并判定

**Files:**
- Create: `results/23_camels_switch_confirmation/camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_20260812_local/`
- Create: `tmp/camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_run.stdout.log`
- Create: `tmp/camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_run.stderr.log`
- Create: `tmp/camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_verify.stdout.log`
- Create: `tmp/camels_parfc_day540_truth_state_counterfactual_07184000_s0_01_verify.stderr.log`

**Interfaces:**
- Consumes: 冻结原始高斯九路径结果和已测试运行器。
- Produces: 可重载、可核验的单任务因果诊断。

- [ ] **Step 1: 首查身份、输出不存在和冻结指纹**

  要求分支 `codex/camels-rising-half-recal`、提交 `61e938b3a89f648e460a20e6f03e005bdc9fca4a`、无同名运行进程、全新输出和日志均不存在。

- [ ] **Step 2: 运行一个反事实任务**

  从第0天重放至第1259天，仅在第540天更新前执行一次状态均值替换。

- [ ] **Step 3: 独立重载核验**

  要求概率与稳定对数概率可由重跑结果逐位复现，干预次数恰为1，协方差和概率在干预瞬间未改变，冻结指纹未改变。

- [ ] **Step 4: 报告因果指标**

  对照冻结原始高斯九路径结果，报告第540—719天真实候选概率归零天数、平均概率、布赖尔分数、平均负对数概率、30天响应门和第719天概率；另报告第720—899天，判断故障是消失还是仅后移。

- [ ] **Step 5: 限定结论**

  若唯一状态替换使第540天事件由失败变为通过并显著解除概率崩塌，则支持“错误完整状态经容量映射放大是该段失败的主要触发因素”；否则拒绝该单因素解释。任何结果均不得解释为可运行修复或跨流域有效性。

## Self-Review

- Spec coverage: 覆盖流域、种子、原始高斯、唯一干预、十五状态、冻结证据、全新输出、因果边界和禁止扩展。
- Placeholder scan: 无待定项或未定义接口。
- Type consistency: 运行器、测试、输出和核验均使用相同实验编号、路径和第540天更新前时序。

## Execution Handoff

用户已明确选择在当前对话内继续执行；按内联执行处理，不派生代理，不提交代码。
