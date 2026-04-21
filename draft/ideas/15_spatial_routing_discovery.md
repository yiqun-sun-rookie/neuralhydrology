# Idea 15: Spatial Routing Discovery

**状态**: archived
**创建日期**: 2026-03-20 左右
**最后更新**: 2026-04-21

---

## 核心问题

CNN 是否能从合成 DEM + 降雨输入中自动"发现"空间汇流规则？用 drainage correlation / dynamic response 等指标评估 CNN 特征图与真实 D8 水流路径的契合度。

---

## 任务隔离边界

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/_archive/15_spatial_routing_discovery/` | 归档，合成 DEM、D8 模拟器、RoutingCNN、分析工具 |
| Results | — | 本地运行产物已清空（均为 gitignored，未入 VCS），如需恢复从 `src/_archive/.../scripts/` 重跑 |
| Logs | — | 无持续训练日志 |

## 模块组成

- `simulator.py`：D8 水流 + 合成降雨
- `terrain.py`：合成 DEM 生成
- `models.py`：可配置深度的 RoutingCNN + feature map 抽取
- `analysis.py`：drainage correlation / dynamic response
- `dataset.py`：PyTorch Dataset
- `scripts/`：端到端实验 runner、可视化

---

## 进度记录

- 2026-03-20: 最后一次 commit（实验 runner 收尾）
- 2026-04-19: 已注册 ID 15，状态 paused
- 2026-04-21: **归档** — 代码迁至 `src/_archive/15_spatial_routing_discovery/`，本地 results 清空。未来若恢复需重新评估优先级并取消归档
