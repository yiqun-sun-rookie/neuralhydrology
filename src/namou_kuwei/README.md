# namou_kuwei — MOVED

Nam Ou 库尾站 DL 工作区已迁移到兄弟仓库 `laos_forecast`：

- 新位置：`../../../laos_forecast/basins/namou_kuwei/dl/`
- 总览：`../../../laos_forecast/basins/namou_kuwei/PROJECT_OVERVIEW.md`

## 为什么搬走

`neuralhydrology/` 作为纯库不再承载流域特定代码。流域数据（SSOT）和流域工作区（XAJ / DL）均外部化：

- **DL 实验** → `laos_forecast/basins/namou_kuwei/dl/`
- **XAJ 率定** → `forecast_system_lite/basins/namou_kuwei/`
- **SSOT 数据** → `laos_forecast/data/03_final/namou_kuwei/`

## 典型命令

```bash
cd laos_forecast
python -m neuralhydrology.nh_run train \
  --config-file basins/namou_kuwei/dl/configs/no_leak/14_hybrid_clean/<cfg>.yml --gpu 0
```

此目录保留仅为避免误解；可随时删除。
