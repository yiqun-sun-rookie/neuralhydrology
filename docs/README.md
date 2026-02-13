# 文档目录

## 📁 目录结构

```
docs/
├── guides/                    # 用户指南
│   ├── SIMPLE_TRAIN_GUIDE.md # 简单训练指南
│   ├── SIMPLE_TRAIN_USAGE.md # 简单训练使用说明
│   ├── GPU_SETUP_GUIDE.md    # GPU设置指南
│   ├── GPU_TRAINING_README.md # GPU训练说明
│   ├── QUICK_TRAIN_GUIDE.md  # 快速训练指南
│   ├── RESUME_TRAINING_GUIDE.md # 恢复训练指南
│   ├── TRAINING_GUIDE.md     # 训练指南
│   ├── GEE_CAMELS_USAGE.md   # GEE CAMELS使用指南
│   └── GEE_INTEGRATION_GUIDE.md # GEE集成指南
├── technical/                 # 技术文档
│   ├── LAUNCHER_DESIGN.md    # 启动器设计
│   ├── TIME_SPLIT_FIX.md     # 时间分割修复说明
│   ├── TRAINING_SCRIPTS_ANALYSIS.md # 训练脚本分析
│   ├── CLEANUP_SUMMARY.md    # 清理总结
│   ├── ROOT_FILES_ANALYSIS.md # 根目录文件分析
│   └── TRAINING_NAMING_RULES.md # 训练命名规则
└── README.md                 # 本说明文件
```

## 📚 文档分类

### 用户指南 (guides/)
面向用户的使用指南和教程。

#### 训练相关
- **`SIMPLE_TRAIN_GUIDE.md`** - 详细的训练指南
- **`SIMPLE_TRAIN_USAGE.md`** - 快速使用说明
- **`QUICK_TRAIN_GUIDE.md`** - 快速训练指南
- **`RESUME_TRAINING_GUIDE.md`** - 恢复训练指南
- **`TRAINING_GUIDE.md`** - 通用训练指南

#### 硬件相关
- **`GPU_SETUP_GUIDE.md`** - GPU环境设置指南
- **`GPU_TRAINING_README.md`** - GPU训练说明

#### 数据相关
- **`GEE_CAMELS_USAGE.md`** - Google Earth Engine使用指南
- **`GEE_INTEGRATION_GUIDE.md`** - GEE集成指南

### 技术文档 (technical/)
面向开发者的技术文档和设计说明。

#### 系统设计
- **`LAUNCHER_DESIGN.md`** - 启动器设计文档
- **`ROOT_FILES_ANALYSIS.md`** - 根目录文件分析

#### 问题修复
- **`TIME_SPLIT_FIX.md`** - 时间分割问题修复说明
- **`CLEANUP_SUMMARY.md`** - 项目清理总结

#### 开发相关
- **`TRAINING_SCRIPTS_ANALYSIS.md`** - 训练脚本分析报告
- **`TRAINING_NAMING_RULES.md`** - 训练文件命名规则

## 🎯 快速导航

### 新用户入门
1. 阅读 `guides/SIMPLE_TRAIN_USAGE.md` 了解基本使用
2. 查看 `guides/GPU_SETUP_GUIDE.md` 配置环境
3. 参考 `guides/SIMPLE_TRAIN_GUIDE.md` 进行训练

### 开发者参考
1. 查看 `technical/LAUNCHER_DESIGN.md` 了解系统设计
2. 参考 `technical/ROOT_FILES_ANALYSIS.md` 了解项目结构
3. 阅读 `technical/TRAINING_SCRIPTS_ANALYSIS.md` 了解脚本分析

### 问题排查
1. 查看 `technical/TIME_SPLIT_FIX.md` 了解时间分割问题
2. 参考 `technical/CLEANUP_SUMMARY.md` 了解项目清理
3. 阅读相关指南文档获取解决方案

## 📖 文档使用建议

### 按需阅读
- **快速开始**: 先读 `SIMPLE_TRAIN_USAGE.md`
- **深入学习**: 再读 `SIMPLE_TRAIN_GUIDE.md`
- **问题解决**: 查看相关技术文档

### 文档维护
- 定期更新文档内容
- 保持文档与代码同步
- 添加新功能的文档说明

## 🔄 文档更新

### 更新原则
1. **及时性**: 代码变更后及时更新文档
2. **准确性**: 确保文档内容准确无误
3. **完整性**: 覆盖所有重要功能
4. **易读性**: 使用清晰的语言和格式

### 更新流程
1. 修改代码后检查相关文档
2. 更新文档内容
3. 检查文档格式和链接
4. 提交文档变更

## 📚 相关资源

### 外部文档
- [NeuralHydrology 官方文档](https://neuralhydrology.readthedocs.io/)
- [PyTorch 官方文档](https://pytorch.org/docs/)
- [Google Earth Engine 文档](https://developers.google.com/earth-engine)

### 项目文档
- `README.md` - 项目主文档
- `PROJECT_OVERVIEW.md` - 项目概览
- `tools/README.md` - 工具脚本说明
- `gee_scripts/README.md` - GEE脚本说明
- `scripts/hpc/README.md` - HPC相关说明

## ⚠️ 注意事项

1. **版本兼容**: 文档内容应与代码版本保持一致
2. **链接检查**: 定期检查文档中的链接是否有效
3. **格式统一**: 保持文档格式的一致性
4. **内容更新**: 及时更新过时的信息
