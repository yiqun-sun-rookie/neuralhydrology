# 全流域训练配置说明

## 📁 配置文件清单

| 配置文件 | 说明 | 静态属性 | 推荐 |
|----------|------|----------|------|
| `full_training_531_temporal_with_static.yml` | 推荐训练配置 | ✅ 14个 | ✅ |
| `full_training_531_temporal_norm_base.yml` | 531流域 baseline（无静态属性） | ❌ | 对照组 |
| `full_training_531_temporal_with_static.yml` | 531流域 + 静态属性 | ✅ 14个 | ✅ **最佳** |

---

## 🏆 训练结果对比

| 配置 | Median NSE | 训练时间 | 备注 |
|------|------------|----------|------|
| **with_static** | **0.747** | ~10h (30 epochs) | 🏆 最佳 |
| norm_base | 0.615 | ~4h (10 epochs) | baseline |

**结论**: 添加静态属性后 NSE 提升 **21.5%**！

---

## ✅ 推荐配置

**使用 `full_training_531_temporal_with_static.yml`**

### 关键特性
- ✅ 531 个基准流域（Kratzert et al., 2019）
- ✅ 14 个静态属性（地形、土壤、植被、气候）
- ✅ 无数据泄露（时间严格分离）
- ✅ NSE 损失函数
- ✅ 最佳验证 NSE: **0.747**

### 时间分割
- **训练集**: 1990-10-01 ~ 1995-09-30 (5年)
- **验证集**: 1995-10-01 ~ 2000-09-30 (5年)
- **测试集**: 2000-10-01 ~ 2005-09-30 (5年)

---

## 🚀 使用方法

```bash
# 推荐：带静态属性的训练
python -m neuralhydrology.nh_run train --config-file src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml --gpu 0

# 对照：无静态属性的 baseline
python -m neuralhydrology.nh_run train --config-file src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_norm_base.yml --gpu 0
```

---

## 📊 静态属性列表

```yaml
static_attributes:
  # 地形 (camels_topo.txt)
  - elev_mean          # 平均高程 [m]
  - slope_mean         # 平均坡度 [m/km]
  - area_gages2        # 流域面积 [km²]
  
  # 土壤 (camels_soil.txt)
  - soil_depth_pelletier  # 土壤深度 [m]
  - soil_porosity         # 土壤孔隙度 [-]
  - sand_frac             # 砂土比例 [%]
  - clay_frac             # 黏土比例 [%]
  
  # 植被 (camels_vege.txt)
  - frac_forest        # 森林覆盖率 [-]
  - lai_max            # 最大叶面积指数 [-]
  - gvf_max            # 最大绿色植被覆盖 [-]
  
  # 气候 (camels_clim.txt)
  - p_mean             # 平均降水 [mm/day]
  - aridity            # 干旱指数 (PET/P) [-]
  - frac_snow          # 降雪比例 [-]
  - high_prec_freq     # 高降水频率 [days/year]
```

---

## 📂 训练结果目录

保留的有效训练结果：

| 目录 | 配置 | NSE | 状态 |
|------|------|-----|------|
| `runs/full_531_temporal_with_static_2025_1127_2057_ep30/` | with_static | 0.747 | ✅ 最佳 |
| `runs/full_531_temporal_norm_base_2025_1124_1916_ep10/` | norm_base | 0.615 | ✅ baseline |

---

## ⚠️ 历史问题记录

### 问题1: 数据泄露（已修复）
- **问题**: 早期配置 `full_674_basins.yml` 存在训练/验证/测试时间重叠
- **解决**: 已删除该配置，所有新配置时间严格分离

### 问题2: 缺少静态属性（已修复）
- **问题**: 原配置未使用流域静态属性，导致 NSE 偏低
- **解决**: 添加 14 个关键静态属性，NSE 从 0.615 提升到 0.747

---

## 📖 详细文档

完整训练报告请参考：`docs/technical/TRAINING_SUMMARY_531_STATIC.md`

