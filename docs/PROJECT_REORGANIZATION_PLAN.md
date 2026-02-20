# NeuralHydrology 项目整理规划

> 本文档由分析生成并经验证修正。**全部阶段已执行完成。** 最后更新：2026-02-20。

---

## 1. 现状总结：当前结构的主要问题

1. **根目录迁移已完成但引用未清理**：`scripts/`、`hpc/`、`tools/` 目录已移除，文件已迁移至 `src/*/scripts` 或 `src/*/hpc`，但文档中的旧路径引用仍需更新。

2. **训练类文档过多且重叠**：同一主题下存在多份文档：
   - `TRAINING_GUIDE`（归档）
   - `QUICK_TRAIN_GUIDE`（归档）
   - `SIMPLE_TRAIN_GUIDE`、`SIMPLE_TRAIN_USAGE`
   - `FULL_TRAINING_GUIDE`
   - `RESUME_TRAINING_GUIDE`（归档）
   - `GPU_TRAINING_README`（归档）
   
   易混淆，且部分引用已废弃脚本（`simple_train.py`、`quick_gpu_train.py`）。

3. **跨 idea 配置与数据重复**：`caravan_daily_smoke_2basins_ep1.yml`、`caravan_daily_smoke_10basins_ep3.yml`、`smoke_2_basins.txt`、`smoke_10_basins.txt` 在 `caravan_global` 与 `mts_mamba_global_transfer` 中几乎相同，存在冗余同步成本。

4. **archive 与 legacy 分布散乱**：`docs/archive` 下有多级子分类（`technical_legacy`、`guides_legacy`、`legacy_guides`、`hpc_legacy`、`dependency_sets`、`migration_backups`），同一文档可能出现在多个子目录。

5. **src 子项目结构不一致**：有的有完整 `README`、`configs`、`hpc`、`scripts`、`docs`，有的缺 hpc、有的缺 docs，命名与层级不统一。

6. **ID 与目录命名混合**：`mts_mamba_global_transfer` 为数字前缀，其余多为 `caravan_global`、`mamba_camels_us` 等语义命名，风格不统一。

7. **中英文混用与敏感内容**：部分文档为中文，部分为英文；根目录曾存在机构资料、密码等本地敏感文件。

8. **full_531_basins 配置双重来源**：`configs/full_training/` 与 `configs/camels_us/full_training/` 并存，职责边界未在文档中清晰说明。

---

## 2. 目录与文件清单

### 2.1 根目录关键结构

```
neuralhydrology/
├── neuralhydrology/          # 核心可导入包
├── src/                       # idea 级代码根
│   ├── caravan_global/
│   ├── mamba_camels_us/
│   ├── mamba_camelsh/
│   ├── namou_kuwei/
│   ├── full_531_basins/
│   ├── haihe_river/
│   ├── hydroagent/
│   ├── mts_mamba_global_transfer/
│   ├── global_hourly_model/   # 候选 idea（占位）
│   └── test_data/             # 共享测试数据
├── docs/                      # 工程文档
├── draft/                     # 研究/论文草稿
├── results/                   # 按 ID_idea 的结果
├── logs/                      # 按 ID_idea 的日志
├── data/                      # 本地数据集
├── common/                    # 共享 HPC 工具
├── examples/                  # 教程 notebook
├── test/                      # neuralhydrology 测试
├── runs/                      # 临时运行目录
├── external/                  # 本地外部资源（gitignore）
├── requirements*.txt
├── setup.py
└── README.md
```

### 2.2 各区域文件数量（约数）

| 区域 | 数量 |
|------|------|
| docs/*.md + docs/**/*.md | ~100+ |
| docs/archive/** | 59 |
| docs/guides/ | 15 |
| docs/hpc/ | 5 |
| docs/technical/ | 12 |
| src/*/configs/*.yml | 125 |
| src/*/scripts/*.py | 80+ |
| src/*/hpc/* | 20+ |
| common/ | 14 |
| examples/ | 25 |

### 2.3 src 子项目目录结构概览

| 子项目 | README | configs | hpc | scripts | docs | data | pipelines |
|--------|--------|---------|-----|---------|------|------|-----------|
| caravan_global | ✅ | ✅ | ✅ | ✅ | 部分 | ✅ | - |
| mamba_camels_us | ✅ | ✅ | ✅ | - | 部分 | ✅ | - |
| mamba_camelsh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | - |
| namou_kuwei | 无根 README | ✅ | - | ✅ | ✅ | - | - |
| full_531_basins | 有 docs/ | ✅ | ✅ | ✅ | ✅ | ✅ | - |
| haihe_river | ✅ | ✅ | - | ✅ | ✅ | - | ✅ |
| hydroagent | - | ✅ | - | - | 部分 | - | - |
| mts_mamba_global_transfer | ✅ | ✅ | ✅ | - | - | ✅ | - |
| test_data | - | ✅ | - | ✅ | - | - | - |
| global_hourly_model | - | 占位 | - | - | - | - | - |

---

## 3. 冗余与版本清单

### 3.1 docs 中同一主题多版本

| 主题 | 活跃位置 | 归档/重复位置 |
|------|----------|----------------|
| 训练入门 | QUICK_START.md | QUICK_TRAIN_GUIDE (guides_legacy) |
| 简单训练 | SIMPLE_TRAIN_GUIDE.md, SIMPLE_TRAIN_USAGE.md（已标注 Deprecated） | legacy_guides/SIMPLE_TRAIN_* |
| 531 训练 | FULL_TRAINING_GUIDE.md | - |
| GPU 训练 | GPU_SETUP_GUIDE.md | GPU_TRAINING_README (guides_legacy) |
| 断点续训 | - | RESUME_TRAINING_GUIDE (guides_legacy) |
| HPC 部署 | HPC_WORKFLOW_FINAL.md, HPC_MIGRATION_GUIDE.md | HPC_DEPLOYMENT_GUIDE/PLAN/SUMMARY (hpc_legacy) |
| 分享/协作 | - | LIGHTWEIGHT_SHARING_GUIDE, SHARING_CHECKLIST (technical_legacy + legacy_guides) |
| 训练脚本分析 | - | TRAINING_SCRIPTS_ANALYSIS (technical_legacy + legacy_guides) |

### 3.2 配置重复与多来源

- **Smoke 配置**：`caravan_daily_smoke_2basins_ep1.yml`、`caravan_daily_smoke_10basins_ep3.yml` 在 `caravan_global` 与 `mts_mamba_global_transfer` 中各一份，逻辑等价。
- **Basin 列表**：`smoke_10_basins.txt` 在 caravan_global 与 41_mts_mamba 中内容相同（可合并）；mamba_camels_us、mamba_camelsh 的列表包含各自数据集的 basin，内容不同，不应合并。
- **full_531 配置**：`full_training/*.yml` 与 `camels_us/full_training/*.yml` 部分重叠。

### 3.3 namou_kuwei 内部版本/归档

- `docs/` vs `docs/archive/`：多份文档在根 docs 和 archive 中各有一份。
- `configs/archive_legacy/`：含 `model_leadtime/`、`leadtime_v4/`、`leadtime/` 等多个版本区，共 40+ 个遗留配置。

### 3.4 common 与 scripts 遗留

- `common/archive/legacy/`：含旧 HPC 脚本。
- `docs/archive/examples_legacy/`：`test_enc.py`、`test_encoding.py` 等已废弃脚本。

---

## 4. 整理原则建议

### 4.1 命名与层级

- **idea 目录**：统一采用 `src/<slug>/`，slug 为语义名（如 `caravan_global`），不再使用数字前缀（如 `41_`），数字 ID 仅用于 results/logs。
- **archive**：单一归档根 `docs/archive/`，不再分 `*_legacy`、`legacy_*` 多级，可用子目录按年份或主题分（如 `2025_migration`、`deprecated_guides`）。
- **配置**：idea 内配置仅放 `src/<idea>/configs/`，若有 legacy 则用 `configs/archive/` 或 `configs/deprecated/` 子目录。

### 4.2 职责划分

- **根目录**：仅保留项目元信息、构建入口、全局依赖；不保留 scripts、hpc、configs。
- **docs/**：顶层 guides、hpc、technical 为共享工程文档；idea 专属文档在 `src/<idea>/docs/`。
- **common/**：仅保留跨 idea 的 HPC 工具；idea 专属脚本一律在 `src/<idea>/hpc/` 或 `scripts/`。
- **examples/**：仅教程与示例，不作为 `src/*` 生产配置或脚本的依赖。

### 4.3 文档入口

- 训练入口：`QUICK_START` → `FULL_TRAINING_GUIDE`（按 idea 分章节），废弃的 `SIMPLE_TRAIN_*` 在 README 中指向新入口后删除或并入 archive。
- HPC：`HPC_QUICK_START` → `HPC_WORKFLOW_FINAL`，其他 HPC 文档并入或归档。

---

## 5. 分阶段整理计划

### Phase 0：CI/CD 修复（已完成 ✅）

1. ~~`pytest-ci.yml`：从 conda 切换为 pip，引用 `requirements-cpu.txt`~~
2. ~~`docs-ci.yml`：`environments/rtd_requirements.txt` → `docs/requirements.txt`~~
3. ~~创建 `docs/requirements.txt`（从归档恢复）~~

### Phase 1：文档与引用梳理（低风险）

1. 在 `docs/guides/README.md` 中建立单一入口：INSTALLATION → QUICK_START → 按 idea 的训练指南，并标注 `SIMPLE_TRAIN_*` 为 Deprecated。
2. 将 `SIMPLE_TRAIN_GUIDE.md`、`SIMPLE_TRAIN_USAGE.md` 移入 `docs/archive/deprecated_guides/`，并在原位置留重定向说明。
3. 合并 `docs/archive/technical_legacy` 与 `docs/archive/legacy_guides` 中重复文档，只保留一份，更新内部交叉引用。
4. 扫描全库中对 `simple_train.py`、`quick_gpu_train.py`、`gpu_training.py` 的引用并替换或标注废弃。
5. 为 `docs/archive` 编写顶层 `README.md`，说明各子目录用途与保留策略。

### Phase 2：配置与 smoke 去重（中风险）

1. 合并 `caravan_global` 与 `41_mts_mamba` 的等价 smoke 配置和 basin 列表（仅这两者内容相同）；其他项目的 basin 列表各有独立意义，保持不变。
2. 明确 `full_531_basins` 中 `full_training/` 与 `camels_us/full_training/` 的职责，并在 README 中说明。
3. 对 `namou_kuwei/docs` 与 `docs/archive` 的重复文档做合并或删除，保留单一权威版本。
4. 将 `namou_kuwei/configs/archive_legacy/` 下不再使用的子目录标记为只读或移入更深的 archive。

### Phase 3：根目录与子项目结构统一（较高风险）

1. 确认根目录已无 `scripts/`、`hpc/`、`tools/` 的活跃引用；若有，更新至 `src/<idea>/` 对应路径。
2. 为每个 src 子项目建立统一模板：README、configs、hpc（如有）、scripts、docs 目录，缺失的补齐或明确标注「无」。
3. 考虑将 `mts_mamba_global_transfer` 重命名为 `mts_mamba_global_transfer`，并在 results/logs 中保留 `41_` 前缀以兼容现有记录。
4. 清理 `common/archive/legacy/`，仅保留确有历史价值的文件，其余删除或移入 `docs/archive/scripts_legacy/`。
5. 将 PDF、敏感文件移出根目录，放入 `docs/hpc/reference/` 或 `external/`，并确保 `.gitignore` 生效。

---

## 6. 风险与注意事项

1. **路径引用**：大量文档和脚本中硬编码了 `src/<idea>/...` 路径，移动或重命名目录需全局搜索替换。
2. **CI/CD**：若存在 GitHub Actions 等，需检查 `config-file`、`run-dir`、`results/` 路径是否与整理后的结构一致。
3. **SLURM 与 HPC**：`sbatch src/<idea>/hpc/*.slurm` 依赖当前路径，修改 `src` 结构或工作目录会直接影响 HPC 脚本。
4. **neuralhydrology 包**：`neuralhydrology/hydroagent` 与 `src/hydroagent` 可能存在交叉引用，需确认运行时代码入口与导入路径。
5. **data/ 与 results/**：`.gitignore` 已忽略这些目录，整理时主要关注路径文档与脚本。
6. **中文与编码**：脚本中多处有编码设置，修改或移动脚本时需保持完整。
7. **draft/ideas/**：各 idea 文档中引用了 `src/<idea>/`、`results/<ID>_<idea>/`，结构变更后需同步更新。

---

## 7. 执行检查清单（供执行时使用）

- [x] Phase 0 完成：CI/CD 引用已修复
- [x] Phase 1 完成：文档入口建立，archive 去重，废弃引用清理
- [x] Phase 2 完成：smoke 配置标注，namou_kuwei 去重，full_531 职责明确
- [x] Phase 3 完成：41_mts 重命名（零残留），子项目 README 补全，legacy 清理
- [ ] 后续：运行 smoke 测试验证训练流程；HPC 提交测试作业验证路径

---

*本文档为规划用途，实际执行前请逐项复核。*
