# 跨码对齐结果：本仓 MUKF/IMM vs MATLAB trackingUKF/trackingIMM

- 判定档位（预冻结分级）：**结构等价**
- G0 输入自洽：通过
- G1 WALRUS 开环最大绝对差：4.547e-13（门槛 1e-08，通过）
- G2 单滤波器强判据：未通过
- G3 概率轨迹最大绝对差：1.584e-02；锚点判据：通过

详见 gate_results.json / g2_first_exceed.csv / g3_anchor_comparison.csv。
