# HydroAgent: 项目执行指南与 Agent 核心逻辑

## 1. 项目核心理念
**目标**：构建一个“数字水文学家”（Digital Hydrologist）。
**差异化**：
- 传统方法（NAS/遗传算法）：基于随机变异或梯度，"知其然不知其所以然"。
- **HydroAgent**：基于 LLM 的语义推理。像人类专家一样，通过阅读流域属性提出假设，根据诊断报告的物理反馈（如“洪峰滞后”、“基流不足”）有逻辑地修改模型结构。

---

## 2. 系统架构 (The Trinity)

项目分为三个相互协作的模块：

| 模块 | 角色 | 职责 | 状态 |
| :--- | :--- | :--- | :--- |
| **Module A** | **诊断官 (Diagnostics)** | **"眼睛"**。不仅计算 NSE，还负责“看病”。输出结构化的病理报告（如：双峰效应、退水过快）。 | 待开发 |
| **Module B** | **执行者 (Environment)** | **"手脚"**。封装 SuperflexPy。接收 JSON 结构，自动完成代码构建和参数率定（Auto-Calibration）。 | 开发中 |
| **Module C** | **大脑 (Agent)** | **"指挥官"**。基于 LLM。阅读属性 -> 提出结构 -> 接收诊断 -> 逻辑修正。 | 核心任务 |

---

## 3. Agent 核心工作流 (The Discovery Loop)

这是 Agent 真正体现“智能”的闭环过程。

### Step 1: 感知与假设 (Perception & Hypothesis)
- **输入**: CAMELS 流域属性 (e.g., 坡度陡、岩溶地貌、干旱区).
- **Agent 思考**: 
  > "这是一个岩溶流域，传统的单水库模型肯定会导致枯水期模拟不足。我假设需要一个慢速并联水库来模拟深层地下水。"
- **输出**: 初始模型结构 JSON (Structure V1).

### Step 2: 执行与率定 (Execution via Module B)
- **动作**: Agent 将 JSON 发送给 Module B。
- **过程**: Module B 自动构建 SuperflexPy 对象，使用 L-BFGS-B 算法自动寻找该结构下的最优参数 ($k, \alpha, S_{max}$)。
- **输出**: 模拟流序列 ($Q_{sim}$) + 基础评分 (NSE=0.55).

### Step 3: 诊断与反馈 (Diagnosis via Module A)
- **动作**: 将 $Q_{obs}$ 和 $Q_{sim}$ 发送给 Module A。
- **过程**: Module A 运行 `Windowed Peak Matching` 和 `Recession Analysis`。
- **输出**: **结构化诊断报告**。
  ```json
  {
    "status": "warning",
    "issues": [
      {"type": "Peak_Lag", "value": "+5h", "desc": "洪峰显著滞后"},
      {"type": "Low_Flow_Bias", "value": "-40%", "desc": "基流严重低估"}
    ]
  }
  ```

### Step 4: 推理与修正 (Reasoning & Refinement)
- **输入**: 初始结构 JSON + 诊断报告。
- **Agent 思考 (Chain of Thought)**:
  > "NSE 0.55 不够好。诊断报告指出'洪峰滞后 5 小时'，说明我的汇流路径太长了，或者 lag function 设置不当。同时'基流低估'验证了我最初关于岩溶的担忧，但我可能把慢速水库的参数范围设得太小了，或者连接方式不对。
  > **修正计划**: 1. 移除 Lag Function 以解决滞后；2. 将慢速水库改为独立并联，直接汇入河道。"
- **输出**: 修正后的模型结构 JSON (Structure V2).

---

## 4. 任务分工与协作

### 给 协作者/Worker A (诊断组) 的指令
**你的产出是 Agent 的眼睛。**
请实现 `HydroDiagnostician` 类：
1. **输入**: 观测与模拟时间序列。
2. **核心功能**: 实现 `Windowed Peak Matching` 算法，解决“双峰干扰”问题；识别“快/慢”流过程的系统性偏差。
3. **输出**: 必须包含自然语言描述的 `semantic_feedback` 字段，供 Agent 阅读。

### 给 协作者/Worker B (环境组) 的指令
**你的产出是 Agent 的手脚。**
请实现 `SuperflexEnv` 类：
1. **接口**: 严格遵守 `docs/technical/HYDRO_AGENT_SPEC.md` 中的 JSON 协议。
2. **核心功能**: 
   - `build_from_json()`: 将 JSON 解析为 SuperflexPy 的 Unit/Node 网络。
   - `auto_calibrate()`: 内置 `scipy.optimize`，自动把参数调到最优。Agent 不负责调参，只负责搭积木。
3. **鲁棒性**: 遇到非法图结构（如死循环），请捕获异常并返回极低的 Reward，不要让程序崩溃。

---

## 5. Agent 代码逻辑预览 (Pseudo-Code)

```python
class HydroAgent:
    def __init__(self, llm):
        self.llm = llm

    def solve_catchment(self, attributes, obs_data):
        # 1. 初始猜测
        structure = self.llm.generate_initial_hypothesis(attributes)
        
        for iteration in range(5): # 迭代 5 轮
            # 2. 自动率定 (调用 Module B)
            env = SuperflexEnv()
            sim_flow, trained_params = env.run(structure, obs_data)
            
            # 3. 诊断评估 (调用 Module A)
            doctor = HydroDiagnostician()
            report = doctor.diagnose(obs_data, sim_flow)
            
            # 4. 修正结构 (调用 Module C/LLM)
            prompt = f"""
            当前结构: {structure}
            诊断反馈: {report['semantic_feedback']}
            请分析原因并生成改进后的 JSON。
            """
            structure = self.llm.refine_structure(prompt)
            
        return structure
```
