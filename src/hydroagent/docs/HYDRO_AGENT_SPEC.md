# HydroAgent: 架构与接口技术规范 (V1.0)

## 1. 项目愿景
构建一个基于 LLM Agent 的自动化水文模型发现系统。
- **Core Loop:** Agent (设计结构) -> Environment (构建并率定参数) -> Diagnostics (评估并生成反馈) -> Agent (修正结构)。
- **Goal:** 自动发现适合特定流域物理特征（如岩溶、积雪、干旱）的 SuperflexPy 拓扑结构。

## 2. 模块划分与职责

### Module A: 诊断评价系统 (Diagnostics)
- **职责**: 充当“验尸官”。不仅计算 NSE，还要分析“为什么不好”。
- **输入**: 观测流量 ($Q_{obs}$), 模拟流量 ($Q_{sim}$), 降雨/蒸发 (可选, 用于分析响应)。
- **输出**: 结构化的诊断报告 (JSON/Dict) + 自然语言描述。
- **关键算法**: Windowed Peak Matching (抗双峰干扰), Recession Analysis, Flow Duration Curve Signature.

### Module B: 自动化建模环境 (Environment)
- **职责**: 充当“执行者”。将抽象的结构描述转化为可运行的代码，并自动寻找最优参数。
- **输入**: 模型结构描述 (Structure JSON), 气象驱动数据 (Forcing Data).
- **输出**: 模拟流量序列 ($Q_{sim}$), 优化后的参数值, 基础 Loss (NSE).
- **关键技术**: SuperflexPy 封装, Scipy (L-BFGS-B) 自动率定, NetworkX 图校验.

---

## 3. 接口定义 (Interface Contract) - **核心**

### 3.1 数据标准 (Data Protocol)
所有时间序列数据统一使用 **Pandas DataFrame / Series**。
- **Index**: `datetime64[ns]` (UTC)
- **Columns**: 
    - `qobs`: 观测流量 (mm/h 或 m3/s, 需统一)
    - `qsim`: 模拟流量
    - `prcp`: 降雨
    - `ep`: 潜在蒸发

### 3.2 模型结构描述协议 (Structure JSON Schema)
Module B 必须能解析，Agent 必须能生成。

```json
{
  "model_name": "structure_v1",
  "layers": [
    {
      "id": "soil_reservoir",
      "type": "UnsaturatedReservoir", 
      "parameters": ["Smax", "beta"],  // 仅声明需要哪些参数，无需指定值，值由自动率定决定
      "inputs": ["prcp"],
      "outputs": ["out_flux", "evap_flux"]
    },
    {
      "id": "fast_response",
      "type": "PowerReservoir",
      "parameters": ["k", "alpha"],
      "inputs": ["soil_reservoir.out_flux"], // 引用上游输出
      "outputs": ["q_fast"]
    }
  ],
  "lag_functions": [
    {"id": "routing_delay", "input": "q_fast", "type": "GammaLag"}
  ],
  "system_output": ["routing_delay", "slow_response"] // 最终汇集到河道的通量
}
```

### 3.3 诊断报告协议 (Diagnostic Report Schema)
Module A 输出给 Agent 的反馈。

```json
{
  "metrics": {
    "NSE": 0.65,
    "KGE": 0.70,
    "Peak_Lag_Hours": 5.0,  // 滞后5小时
    "Peak_MAPE": 0.25,      // 峰值误差25%
    "Low_Flow_Bias": -0.40  // 枯水期偏低40%
  },
  "semantic_feedback": [
    "Critical: 洪峰响应显著滞后 (Lag > 3h)。建议移除滞后函数或减小汇流参数。",
    "Warning: 退水曲线过快，未能捕捉基流。建议增加并联的线性水库作为慢速地下水层。"
  ]
}
```

---

## 4. 开发注意事项
1. **SuperflexPy 版本**: 确保适配最新版 (v1.3.x)。
2. **单位一致性**: 内部计算统一使用 `mm/time_step`。
3. **鲁棒性**: 
   - Module B 遇到非法图结构（如环路）时，不应 Crash，应返回 `NSE = -999` 和错误信息。
   - Module A 遇到 `NaN` 值时应自动插值或忽略，不要报错。
