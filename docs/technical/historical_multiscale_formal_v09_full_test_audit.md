# 历史连续多尺度气象模型版本09完整局部测试审计

## 结论

2026-07-31，在可用物理内存满足版本09启动硬门后，完整局部测试首次通过：

- 命令：`pytest src/26_historical_band_experts/tests -q`
- 结果：`378 passed, 1 warning in 48.35s`
- 测试代码提交：`23575402ab2bae8857ecf80c3081d16af64434a0`
- 分支：`codex/historical-band-experts-pilot`
- 测试前工作区：干净
- 测试前可用物理内存：`13.79 GiB`
- 正式启动硬门：`12.68 GiB`

唯一警告是仓库既有的 Pytest 配置警告：
`Unknown config option: collect_ignore_glob`。没有测试失败。

## 执行说明

首次调用因外层命令工具被设置为1秒超时而终止，没有残留测试进程，也没有产生测试结论。
随后在可用物理内存仍为`13.46 GiB`时，使用相同命令和正常时限重新执行，得到上述完整通过结果。
测试后可用物理内存为`13.50 GiB`。

## 通过后的边界核验

- 协议JSON SHA-256：
  `b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8`
- 严格嵌套、经典近期、同参数量控制和连续历史四个配置均精确绑定该协议哈希。
- 相对版本09实施父提交
  `75d02d295236b20edc4a593c452d568ce5515dce`，
  `src/fair_benchmark/frozen/`和`src/fair_benchmark/score.py`没有改动。
- 两个可能的正式结果目录均不存在：
  - `results/26_historical_band_experts/formal_v09`
  - `results/26_historical_band_experts/historical_multiscale_formal_v09`
- 正式目标包生成、训练、正式预测和正式评分授权仍全部为`false`。

## 证据边界

这次结果证明当前提交的全部历史分段专家局部测试通过；它不证明531流域输入存在，
不证明30轮严格嵌套训练，不证明连续历史候选或同参数量控制已经训练，也不证明正式评分结果。
在后续代码提交出现前不重复运行该完整测试。正式输入、训练、预测和评分仍须分别获得明确授权。
