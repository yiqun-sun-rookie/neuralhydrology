# 07 - HydroAgent: LLM-based Hydrological Model Structure Discovery

**状态**: dev → **PIVOT 到「可辨识性闸门」方法论文**（2026-07-23）。两条实验线均无正效果证据，详见下方状态更新。
**创建日期**: 2026-01-01
**最后更新**: 2026-07-23

> ⚠ **旧状态说明**：本文件头部曾写"Phase 2 agent loop validated — 4/4 CAMELS basins reach NSE target"。该结论只在**样本内（率定期）**成立；2026-07 的公平留出检验已将其**证伪**——AI 发现的结构在密封留出期塌陷（过拟合不泛化）。旧诊断/Agent 循环代码仍有效，被证伪的只是"AI 无约束搜结构能产出有竞争力模型"这一命题。

---

## 状态更新 2026-07-23：效果合并判定（两条实验线均无正效果证据）

**这是当前最新、覆盖上方 2026-03 旧状态的判定。**

- **纯概念线**（`results/07_hydroagent/cc_discover/fair_*`，15 河公平留出，CMA-ES 5000×3，repro_v01 + Priestley-Taylor PET）：AI 结构留出中位 **0.52 / 0.671**（剔 2 河数值发散），输传统模型 **10/15**、输 LSTM **13/15** → **干净的负结果**（样本内好、留出崩＝过拟合不泛化）。已双重独立验证（主分析 + 独立上下文从原始 `_holdout_5k3.json` 重算 + 5 项对抗挑错全过）。→ 原"退一步对比论文"方向 **PIVOT**。

- **混合线**（`.worktrees/hydroagent-compositional-discovery/results/07_hydroagent/cd/screen_v02/`，12/72 单元后因内存不足停止，2 河 11 完整单元 × 2 方向 × 3 种子）：经两个互不通气的独立审计——
  - **机械层可信**：55 个家族分数从原始 USGS 观测 **bit-exact 重算（误差 1e-13）**；选择流程 **11/11 验证"入选结构 = 选择窗 argmax"，无观测泄漏**；批内 LSTM 0/11 全胜混合确实发生。
  - **科学层作废**：存在 **PET≡0 数据 bug**——本仓 Maurer 强迫文件 **Tmax 恒等于 Tmin**（已亲手核实），Hargreaves 公式的 √(Tmax−Tmin) 因子 = 0 → **蒸发潜力输入每天每河恒为 0**，砍掉语法里所有物理 ET 通路（06452000 的 −21~−36 灾难分即由此判死，非模型差）；叠加 **LSTM 基线三重不对称**（预算集中：1600 步全给单模型 vs 混合摊 16 候选×100 步 / 训练配方精调 NSE-loss+LR 调度+梯度裁剪 vs 混合固定 lr0.01+MSE / 无质量守恒约束）→ **架构级结论无效**（"测不出"，不是"测出没效果"）。
  - **处置**：剩余 60 单元**不按原样跑**（等于在污染协议上烧算力）；任何重启前置＝修 `compositional_discovery/data.py` 的 PET（改用 Priestley-Taylor 或带 Ra 的 Hargreaves，参考本仓 PET-bug 前科）+ 修基线对称性 + 把 `compositional_discovery/` 包纳入 git（当前未跟踪，无法排除代码漂移）。

- **战略转向**：负结果不是死路，正是 **「可辨识性闸门」方法论文**的核心论据——无约束地让 AI 搜水文模型结构，要么过拟合不泛化（纯概念线），要么结构跨种子不复现（混合线：agent/genetic 跨 3 种子基本 3 结构，agent 约半数单元收敛回 fixed 基线结构）。让"效果"转正只有两条路：修混合线 bug 重跑（赌 <20% 翻盘）或给搜索加约束（闸门，主线方向）。

- **证据与细节**：memory `hydroagent_fair_comparison_pivot_20260722` / `hydroagent_screen_v02_audit_20260722`；批量中断原因＝可用内存 395MB 跌破保留线 609MB 触发优雅停止（有 `resources.jsonl` 日志实锤）。

---

---

## 研究目标

构建基于 LLM Agent 的自动化水文模型发现系统 ("数字水文学家")。利用 LLM Agent + SuperflexPy 自动发现适应不同流域特征 (岩溶/积雪/干旱) 的物理模型结构，实现可解释的 AI 水文建模。

**Core Loop**: Agent (设计结构) -> Environment (构建+率定) -> Diagnostics (评估+反馈) -> Agent (修正结构)

---

## 任务隔离边界

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/hydroagent/` | Agent、Environment、Diagnostics 模块 |
| Results | `results/07_hydroagent/` | 验证输出、测试结果 |
| Logs | `logs/07_hydroagent/` | 运行日志 |
| Docs | `draft/ideas/07_hydroagent.md` | 本文档 |
| Index | `draft/RESEARCH_INDEX.md` | 主索引 |

---

## 模块架构

| Module | 文件 | 职责 | 状态 |
|--------|------|------|------|
| **A: Diagnostics** | `src/hydroagent/diagnosis.py` | 多维诊断评价 (NSE + 语义反馈) | **complete** — 21 指标 + 22 条反馈规则 (含 5 个跨领域指标) |
| **B: Environment** | `src/hydroagent/environment.py` | 自动化 SuperflexPy 建模+率定 | **simplified** — 未接入 SuperflexPy |
| **C: Agent** | `src/hydroagent/agent.py` | LLM 交互与推理循环 | **complete** — 5 backends (Claude/DeepSeek/OpenAI/Ollama/Mock), 27 tests, 4-basin validation |

### Module A 核心算法
- Windowed Peak Matching (抗双峰干扰)
- 谱分析 (抗过平滑)
- 最优传输 / Wasserstein (时空错位检测)
- 起涨点检测
- 退水分析 (Recession Analysis)
- 流量历时曲线特征 (FDC Slope Error)
- **跨领域指标** (Cross-Domain Metrics):
  - Hjorth Parameters (脑电信号分析 → 变异性/闪急性/复杂度)
  - 1D-SSIM (图像质量评估 → 局部结构相似度)
  - ITAE (控制工程 → 时间加权误差分布)
  - TF Misfit (地震学 Kristekova → 振幅vs时间误差分离)
  - Perkins Skill Score (气候科学 → 流量分布重叠度)

### Module B 核心技术
- 基于 NetworkX 的自定义 DAG 拓扑引擎
- JSON 动态结构描述 -> SuperflexPy 模型构建
- scipy.optimize 自动参数率定 (L-BFGS-B / Nelder-Mead)

---

## Code Index

| Component | Path | Description |
| :--- | :--- | :--- |
| Diagnostics | `src/hydroagent/diagnosis.py` | Module A: 诊断评价系统 |
| Environment | `src/hydroagent/environment.py` | Module B: 自动化建模环境 |
| Agent | `src/hydroagent/agent.py` | Module C: LLM 智能体 (待开发) |
| Tests | `src/hydroagent/tests/` | 单元测试和集成测试 |
| Demo | `src/hydroagent/examples/hydroagent_demo.py` | 全流程演示 |
| Spec | `src/hydroagent/docs/HYDRO_AGENT_SPEC.md` | 架构与接口规范 |
| Workflow | `src/hydroagent/docs/HYDRO_AGENT_WORKFLOW.md` | 工作流文档 |
| Diagnostics Manual | `src/hydroagent/docs/MODULE_A_DIAGNOSTICS_MANUAL.md` | Module A 用户手册 |

---

## Results Index

| Output | Path | Notes |
| :--- | :--- | :--- |
| Module A Validation | `results/07_hydroagent/module_a_validation/` | 诊断系统验证结果 |
| Multi-Basin DeepSeek | `results/07_hydroagent/multi_basin_deepseek/` | 4 basin × DeepSeek 结构发现实验 (2026-03-02) |

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
| 2026-02-18 | 兼容层下线 | 删除 `neuralhydrology/hydroagent/{agent,diagnosis,environment}.py` 转发模块；旧入口改为明确 ImportError，统一只保留 `src/hydroagent/` |
| 2026-01-01 | 项目启动 | 架构设计与接口定义 |
| 2026-01-15 | Module A 完成 | V1.1 Enhanced 诊断系统 |
| 2026-02-01 | Module B 完成 | NetworkX DAG 引擎 + 自动率定 |
| 2026-02-10 | Phase 1 闭环 | 集成验证通过 (hydroagent_demo.py) |
| 2026-02-10 | 目录迁移 | 从 neuralhydrology/hydroagent/ 迁移到 src/hydroagent/ |
| 2026-02-24 | Module A 重写 | 完整重写 diagnosis.py：13 指标 + 14 条反馈 + NaN 防护 + 退水/FDC 分析 |
| 2026-02-25 | 跨领域指标 | 新增 5 个跨领域指标 (Hjorth/SSIM/ITAE/TF-Misfit/Perkins)，总计 21 指标 + 22 反馈规则，21/21 测试通过 |
| 2026-03-02 | Module C 完成 | Agent loop + 5 LLM backends + MockLLMClient 27 tests |
| 2026-03-02 | ClaudeClient 升级 | claude-opus-4-6 + adaptive thinking + structured outputs + streaming |
| 2026-03-02 | 多流域验证 | DeepSeek × 4 basins: 全部达到 NSE≥0.6，寒冷流域自动发现 SnowReservoir (NSE 0.15→0.84) |

---

## 论文规划

| Paper | 主题 | 状态 |
|-------|------|------|
| Paper 1 | Diagnostic Framework (诊断体系) | 素材就绪 |
| Paper 2 | Differentiable/Automated Environment (环境封装) | 素材就绪 |
| Paper 3 | Agentic Discovery (旗舰论文) | 待 Phase 2 完成 |

---

## Phase 2: Agent Development ✅ COMPLETE

1. ✅ 设计 System Prompt (角色: 资深水文学家)
2. ✅ 实现 `reasoning_loop`: 观察 -> 思考 -> 行动
3. ✅ 集成 LLM API (OpenAI/DeepSeek/Claude/Ollama + MockLLM)
4. ⬜ 可选: RAG 知识库 (SuperflexPy 组件文档)
5. ✅ 实验验证: CAMELS-US 4 个典型流域 (全部 NSE≥0.6)
6. ⬜ 基准对比: LSTM vs Human Expert vs HydroAgent

## 下一步 (Phase 3: Paper-Ready Experiments)

1. **多 LLM 对比**: 同 4 basin 跑 DeepSeek vs Claude vs Gemini，对比结构发现质量和收敛速度
2. **扩展流域数**: 10-20 个 CAMELS basins 覆盖更多气候类型 (干旱/岩溶/城市化)
3. **基准对比**: 同流域同时段的 CudaLSTM/EALSTM 结果 vs HydroAgent
4. **消融实验**: 去掉诊断反馈/去掉 thinking/用随机结构 → 量化各模块贡献
5. **实验日志系统**: 自动保存每轮 LLM 响应、结构 JSON、参数、NSE 到 CSV
6. **论文写作**: Paper 3 (Agentic Discovery) 初稿
