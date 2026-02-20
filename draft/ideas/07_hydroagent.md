# 07 - HydroAgent: LLM-based Hydrological Model Structure Discovery

**状态**: dev
**创建日期**: 2026-01-01
**最后更新**: 2026-02-18

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
| **A: Diagnostics** | `src/hydroagent/diagnosis.py` | 多维诊断评价 (NSE + 语义反馈) | completed |
| **B: Environment** | `src/hydroagent/environment.py` | 自动化 SuperflexPy 建模+率定 | completed |
| **C: Agent** | `src/hydroagent/agent.py` | LLM 交互与推理循环 | pending |

### Module A 核心算法
- Windowed Peak Matching (抗双峰干扰)
- 谱分析 (抗过平滑)
- 最优传输 / Wasserstein (时空错位检测)
- 起涨点检测

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

---

## 论文规划

| Paper | 主题 | 状态 |
|-------|------|------|
| Paper 1 | Diagnostic Framework (诊断体系) | 素材就绪 |
| Paper 2 | Differentiable/Automated Environment (环境封装) | 素材就绪 |
| Paper 3 | Agentic Discovery (旗舰论文) | 待 Phase 2 完成 |

---

## 下一步 (Phase 2: Agent Development)

1. 设计 System Prompt (角色: 资深水文学家)
2. 实现 `reasoning_loop`: 观察 -> 思考 -> 行动
3. 集成 LLM API (OpenAI/DeepSeek)
4. 可选: RAG 知识库 (SuperflexPy 组件文档)
5. 实验验证: CAMELS-US 4 个典型流域
6. 基准对比: LSTM vs Human Expert vs HydroAgent
