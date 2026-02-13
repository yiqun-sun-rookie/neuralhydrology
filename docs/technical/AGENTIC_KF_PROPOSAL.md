# Agentic-KF: 基于智能体增强的自适应数据同化系统
**—— Proposal for Agent-Guided Adaptive Kalman Filtering**

## 1. 核心理念 (Core Concept)
将 **LLM Agent 的认知能力** 与 **IMM-KalmanNet 的计算能力** 相结合，构建一个具备**前瞻性适应能力 (Pre-emptive Adaptation)** 的数字孪生水文同化系统。

## 2. 4-Agent 协同架构 (The Agentic Framework)

本系统由四个分工明确的智能体组成，它们运行在 **IMM-KalmanNet 数学底座**之上。

### 🤖 Agent 1: 感知者 (The Perceiver)
*   **职责**: 获取并融合多源信息。
*   **输入**: 
    - 硬数据: 实时水位 ($Z_k$), 降雨预报 (NWP).
    - **软信息 (关键创新)**: 气象预警文本 ("未来2小时强对流"), 调度指令, 历史相似洪水记录.
*   **输出**: **环境状态向量 (Context Vector)**。例如：`{risk_level: "High", pattern: "Flash_Flood", forecast_trend: "Rising"}`。

### 🤖 Agent 2: 决策者 (The Controller)
*   **职责**: 根据环境状态，决定使用哪个 Filter 或组合。
*   **动作**: **动态调节 IMM 的转移概率矩阵**。
    - *场景 A (平稳期)*: 指令 IMM 锁定在 **Standard KF** (物理性强, 稳定)。
    - *场景 B (突变期)*: 接收到 Agent 1 的暴雨预警，指令 IMM 提升 **KalmanNet** 的先验权重 (非线性强, 响应快)。
*   **底层工具**: 调用 IMM 框架进行概率更新。

### 🤖 Agent 3: 裁判员 (The Evaluator)
*   **职责**: 实时监控系统表现，决定是否需要“换人”。
*   **输入**: 预测残差序列 (Innovation), 似然函数值.
*   **逻辑**: 
    - 如果 `Residual > Threshold` 且持续发散 -> **触发中断**。
    - 向 Agent 2 发送反馈：“当前 KF 正在失效，请立即切换到 KalmanNet 或 Particle Filter！”

### 🤖 Agent 4: 协调员 (The Coordinator)
*   **职责**: 系统的“总管”与“发言人”。
*   **任务**:
    1.  **冲突解决**: 当 Agent 1 (预警) 和 Agent 3 (现状) 矛盾时，根据安全策略做最终裁决。
    2.  **可解释性报告**: 生成最终输出。
        - *用户界面*: "预测水位 12.5m (置信度: 高)"
        - *内部日志*: "系统已自动切换至 KalmanNet，因为 Agent 1 检测到强降雨预警，且 Agent 3 确认标准 KF 残差开始增大。"
    3.  **记忆存储**: 将本次洪水的应对策略存入知识库，供下次复用。

---

## 3. 数学底座 (The Engine: IMM + KalmanNet)

上述 Agent 并不直接进行矩阵运算，而是调度以下数学组件：

1.  **IMM 框架 (Interactive Multiple Model)**:
    - 作为容器，接收 Agent 2 的指令来混合不同的滤波器结果。
    - 公式: $\hat{x}_{final} = \sum w_i \cdot \hat{x}_i$
2.  **Expert A: Standard KF**:
    - 物理守恒，适合稳态。
3.  **Expert B: KalmanNet (working on)**:
    - 利用 LSTM 学习卡尔曼增益 $K$，处理强非线性，适合瞬变态。

---

## 4. 预期价值 (Expected Value)
- **前瞻性**: Agent 1 能读懂预报，实现**事前切换** (Pre-emptive Switching)，优于传统 IMM 的**事后响应**。
- **可解释性**: Agent 4 能告诉用户“为什么”切换模型，打破黑箱。
- **高性能**: 结合了 KF 的稳和 KalmanNet 的灵。
