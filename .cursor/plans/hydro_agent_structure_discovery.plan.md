# HydroAgent: 基于 LLM Agent 的水文模型结构自动发现
> **状态**: ✅ Phase 1: Infrastructure Completed | 🚧 Phase 2: Agent Development (Ready to Start)
> **当前角色**: Main Thread (Project Manager / Architect)
> **最终目标**: 构建一个“数字水文学家”，利用 LLM Agent + SuperflexPy 自动发现适应不同流域特征（岩溶/积雪/干旱）的物理模型结构，实现可解释的 AI 水文建模。

## 📝 对话上下文与进度快照 (Context Restore)
**截至时间**: 2026-02-10
**当前进度**: 
1.  **Phase 1 (基础设施) 已闭环**:
    *   **Module A (诊断评价)**: V1.1 Enhanced 版本已完成。集成 **Windowed Peak Matching** (抗双峰干扰)、**谱分析** (抗过平滑)、**最优传输** (时空错位检测) 和 **起涨点检测**。
    *   **Module B (建模环境)**: 重构完成。实现了基于 NetworkX 的自定义拓扑引擎，解决了 SuperflexPy 原生 Network 类的局限性。支持 JSON 动态构建和 `scipy.optimize` 自动参数率定。
    *   **集成验证**: `examples/hydroagent_demo.py` 已在 CPU 模式下跑通全流程 (数据生成 -> 建模 -> 率定 -> 诊断)。
2.  **文档体系升级**:
    *   新增 `docs/technical/DEVELOPMENT_REPORT.md`: 详细复盘了开发过程与技术突破。
    *   新增 `docs/technical/MODULE_A_DIAGNOSTICS_MANUAL.md`: Module A 的用户手册。
    *   归档了测试结果: `experiments/hydroagent_dev/module_a_validation/`。

**下一步关键动作 (Immediate Next Steps)**:
需要开启新的 Cursor Chat 窗口 (Worker C)，专注于 Phase 2 的 **Agent 智能体开发**：
-   **输入**: 读取 `HYDRO_AGENT_SPEC.md` 和 `MODULE_A_DIAGNOSTICS_MANUAL.md`。
-   **任务**: 实现 `agent.py` 中的 `HydroAgent` 类，完成 LLM 与 Module A/B 的交互闭环。

---

## 🏗️ 模块结构 (Directory Structure)
所有代码位于: `neuralhydrology/hydroagent/`
- `diagnosis.py`: **Module A (诊断)** - [已完成] 多维诊断系统。
- `environment.py`: **Module B (环境)** - [已完成] 自动化建模仿真环境。
- `agent.py`: **Module C (智能体)** - [待开发] 负责 LLM 交互与推理循环。
- `tests/` & `experiments/`: 包含单元测试和验证脚本。

## ✅ 详细任务列表 (Todo List)

### Phase 1: 基础设施构建 (Completed)
- [x] **架构设计 & 接口定义** (Done)
- [x] **Module A: 诊断系统开发** (Done)
    - [x] 实现 `HydroDiagnostician` 类
    - [x] 核心算法: `windowed_peak_matching` (抗双峰干扰)
    - [x] 增强特性: 谱分析、最优传输 (Wasserstein)、起涨点检测
    - [x] 单元测试: `experiments/hydroagent_dev/module_a_validation/test_diagnosis_v2.py`
- [x] **Module B: 自动化环境开发** (Done)
    - [x] 实现 `SuperflexEnv` 类
    - [x] 核心算法: 基于 NetworkX 的自定义 DAG 执行引擎
    - [x] 核心算法: `auto_calibrate` (Scipy L-BFGS-B/Nelder-Mead 封装)
    - [x] 集成测试: `examples/hydroagent_demo.py`

### Phase 2: 智能体构建 (Current Focus)
- [ ] **Agent 核心逻辑 (Module C)**
    - [ ] 设计 System Prompt (角色设定：资深水文学家)
    - [ ] 实现 `reasoning_loop`: 
        1. 观察 (调用 Module A 获取 Report)
        2. 思考 (Chain-of-Thought: 哪里物理机制不对？)
        3. 行动 (生成/修改 Module B 的 Structure JSON)
    - [ ] 集成 LLM API (OpenAI/DeepSeek)
- [ ] **RAG 知识库** (可选)
    - [ ] 整理 SuperflexPy 组件文档供 Agent 查阅

### Phase 3: 验证与论文产出
- [ ] **实验验证**
    - [ ] 数据准备: CAMELS-US 4个典型流域
    - [ ] 基准对比: Pure LSTM vs. Human Expert Model vs. HydroAgent
- [ ] **论文撰写**
    - [ ] Paper 1: Diagnostic Framework (诊断体系)
    - [ ] Paper 2: Differentiable/Automated Environment (环境封装)
    - [ ] Paper 3: Agentic Discovery (旗舰论文)

## 🔗 参考文档
- 开发总结: `docs/technical/DEVELOPMENT_REPORT.md` (必读)
- 诊断手册: `docs/technical/MODULE_A_DIAGNOSTICS_MANUAL.md`
- 架构规范: `docs/technical/HYDRO_AGENT_SPEC.md`
