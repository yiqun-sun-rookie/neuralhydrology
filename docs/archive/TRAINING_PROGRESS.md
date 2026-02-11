# Caravan 全球模型训练进度记录

## 🎯 项目目标

构建全球小时级水文预报模型：
1. **阶段 1**: Caravan 全球日模型 (Pre-training) ← 当前阶段
2. **阶段 2**: MTS-LSTM 迁移学习 (美国小时数据 → 全球)
3. **阶段 3**: 全球推理与验证 (中国数据作为独立测试集)

---

## 📊 当前状态

| 项目 | 状态 | 说明 |
|-----|------|-----|
| 本地训练 | ❌ 失败 | 内存不足 (32GB < 需求 ~40GB) |
| HPC 迁移 | 🔄 进行中 | 脚本已准备，待执行 |
| 数据上传 | ⏳ 待执行 | Caravan 数据需上传到 HPC |

---

## 🖥️ 平台迁移：本地 → HPC

### 决策原因
- **本地内存**: 32GB (不足)
- **HPC 内存**: 可申请 128GB+ (充足)
- **结论**: 将训练迁移到河海大学 HPC

### HPC 配置已完成
- [x] 迁移计划文档: `docs/HPC_MIGRATION_PLAN.md`
- [x] 环境配置脚本: `hpc/setup_hpc_env.sh`
- [x] Slurm 作业脚本: `hpc/slurm_caravan_global.sh`
- [x] HPC 专用配置: `configs/caravan/caravan_daily_basemodel_hpc.yml`

---

## 📝 训练历史

### 本地尝试

#### ❌ 尝试 2: 2025-12-23 22:10
- **平台**: 本地 (32GB RAM, RTX 4070 Ti)
- **结果**: 失败 - 内存溢出
- **最后日志**: `Loading basin data into xarray data set.`
- **诊断**: 7129 流域数据加载需要 ~40GB RAM

#### ❌ 尝试 1: 2025-12-21 12:01
- **平台**: 本地
- **结果**: 中断
- **进度**: Epoch 5/30
- **原因**: 训练卡顿

### HPC 尝试

*(待执行)*

---

## 🚀 下一步行动

### 立即执行 (用户操作)

1. **登录 HPC**
   ```bash
   ssh <username>@hpcbh.hhu.edu.cn
   # 密码: <见密码管理器> + OTP动态码
   ```

2. **运行环境配置**
   ```bash
   bash hpc/setup_hpc_env.sh
   ```

3. **上传 Caravan 数据** (本地执行)
   ```powershell
   scp -r data/Caravan <username>@hpcbh.hhu.edu.cn:/data1/home/<username>/data/
   ```

4. **提交训练作业**
   ```bash
   cd ~/neuralhydrology
   sbatch hpc/slurm_caravan_global.sh
   ```

---

## 📈 预期时间线

| 阶段 | 预计耗时 | 预计完成 |
|-----|---------|---------|
| HPC 环境配置 | 1 小时 | Day 1 |
| 数据上传 | 2-4 小时 | Day 1 |
| Caravan 日模型训练 | 25-30 小时 | Day 2-3 |
| MTS-LSTM 迁移训练 | 10-15 小时 | Day 4 |
| 验证与分析 | 1-2 天 | Day 5-6 |

---

**最后更新**: 2026-01-06
**下一次检查**: HPC 作业提交后
