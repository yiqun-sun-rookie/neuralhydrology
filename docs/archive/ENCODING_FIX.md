# 中文乱码问题修复说明

## 问题描述

在Windows系统上运行 `simple_train.py` 时出现中文乱码问题，影响用户体验。

## 解决方案

### 1. Python脚本修复

在 `simple_train.py` 开头添加了编码设置：

```python
# 设置控制台编码解决中文乱码问题
if sys.platform.startswith('win'):
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.detach())
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.detach())
```

### 2. 批处理文件

创建了 `run_training.bat` 批处理文件，自动设置控制台编码：

```batch
@echo off
chcp 65001 >nul  # 设置控制台为UTF-8编码
```

## 使用方法

### 方法1: 直接使用Python脚本
```bash
python simple_train.py --config examples/01-Introduction/full_training.yml --gpu 0
```

### 方法2: 使用批处理文件（推荐）
```bash
run_training.bat --config examples/01-Introduction/full_training.yml --gpu 0
```

## 修复效果

### 修复前
```
[OK] ҵ conda: neuralhydrology_gpu
[OK] PyTorch汾: 2.2.2
[OK] CUDA: 1GPU豸
```

### 修复后
```
[OK] 找到 conda 环境: neuralhydrology_gpu
[OK] PyTorch版本: 2.2.2
[OK] CUDA可用: 1 个GPU设备
```

## 技术说明

### 编码问题原因
- Windows控制台默认使用GBK编码
- Python输出UTF-8编码的中文字符
- 编码不匹配导致乱码

### 解决方案原理
1. **Python脚本**: 重定向stdout/stderr到UTF-8编码器
2. **批处理文件**: 使用`chcp 65001`设置控制台为UTF-8编码

### 兼容性
- ✅ Windows 10/11
- ✅ Windows PowerShell
- ✅ Command Prompt
- ✅ 跨平台兼容（Linux/macOS不受影响）

## 注意事项

1. **推荐使用批处理文件**: 更简单，自动处理编码
2. **环境变量**: 批处理文件会自动设置OpenMP环境变量
3. **错误处理**: 包含Python环境检查
4. **用户友好**: 提供清晰的状态信息

## 测试验证

所有功能已测试验证：
- ✅ 环境检查正常显示中文
- ✅ GPU检查正常显示中文
- ✅ 帮助信息正常显示中文
- ✅ 批处理文件正常工作

现在可以正常使用，不会再出现中文乱码问题！
