# Streamflow Forecasting Tools

用于快速创建站点模板、生成配置、校验配置并串联训练流程。

## 快速开始

```bash
# 1) 创建站点模板
python tools/new_site.py --name your_site --data-dir data/your_site_hourly

# 2) 生成配置
python tools/gen_config.py --site your_site --type ar --lead 6

# 3) 校验配置
python tools/validate_config.py --dir src/your_site/configs/generated/

# 4) 训练
python tools/run_experiment.py train --config src/your_site/configs/generated/Rain_AR_LT6h.yml
```

## 路径约定

- 站点模板：`src/templates/site_<site>.yml`
- 生成配置：`src/<site>/configs/generated/*.yml`
- 训练输出：`results/<site>/...`（可在模板里自定义）

## 常用命令

```bash
# 预览配置（不写文件）
python tools/gen_config.py --site your_site --type ar --lead 24 --dry-run

# 一键流程：生成 + 校验 + 训练 + 评估
python tools/run_experiment.py quick --site your_site --type ar --lead 1

# 对比结果
python tools/run_experiment.py compare --results-dir results/your_site --metric NSE
```
