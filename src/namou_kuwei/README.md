# namou_kuwei

Nam Ou 库尾站深度学习洪水预报实验。

## Overview

老挝南乌江（Nam Ou）七级电站库尾站的小时级降雨-径流深度学习模型。

## Structure

- `configs/` — 训练配置（`no_leak/` 为当前主力配置，`archive_legacy/` 为历史实验）
- `scripts/` — 数据检查与站点创建脚本
- `docs/` — 项目文档、实验记录、配置参考

## Quick Start

```bash
python -m neuralhydrology.nh_run train \
  --config-file src/namou_kuwei/configs/no_leak/01_baseline/rain_only_LT1h.yml \
  --gpu 0
```

## Detailed Docs

See `docs/README.md` for full project documentation.
