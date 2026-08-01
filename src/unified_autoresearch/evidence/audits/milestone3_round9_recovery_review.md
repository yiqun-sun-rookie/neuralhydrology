# 第三里程碑第九轮恢复复现独立审核

结论：**失败**。

冻结产物本身的证据链完整，但冻结快照源码在全新临时 Git 仓库中不能完成恢复端到端重跑，因此不能准入。

## 阻断项

- 独立运行 `test_registered_recovery_matches_a_clean_deterministic_training_run` 时，`verify_checkpoint()` 报错：`ValueError: checkpoint verified record is missing`。
- `CHECKPOINT_VERIFIED.json` 实际存在且内容完整；其完整路径恰为 260 个字符，源码使用普通 `Path.is_file()` 时错误返回假。
- 测试未执行到重复目标目录必须触发 `FileExistsError` 的断言，因此本次独立重跑也未验证不可覆盖目标拒绝。
- 第八轮依赖源码范围三项定向测试与第七轮候选源码长路径测试均通过，共 4/4。

## 已确认成立的冻结证据

- 三个运行状态依次为 `checkpointed`、`succeeded`、`succeeded`；每个运行均有两次一致的真实调度锁证明、8 条 SQLite 登记和 8 份外部凭据。
- 发布检查点与恢复挂载副本逐字节一致；检查点根散列为 `06a4c8e0684a906d3288c34edc0eac1be5da7a4d98ea2b0a5e86b9630adfeed6`。
- 恢复日志读取 `resume_checkpoint/model.json`，没有读取干净运行目录或评分真值。
- 检查点、恢复和干净模型字节一致，散列均为 `7bb0dca0335bcf387f46799f6d9e8b6d4ce0345a87ca7708797d0a2f47cb2e64`，且不是同一物理文件。
- 合成源仅含 1999-10-01 至 2008-09-30、8 个冻结开发流域及 Maurer 气象驱动；`sealed_final_evaluation_present=false`。
- `RECOVERY_SUMMARY.json` 的 91 项产物清单全部匹配。
- 外层八部分根散列独立重算为 `271c46ebbd9fdd9c851ae2416c6a3bf0af348a4d02deee3f7cffdc4cce8389e2`；359 次文件引用无差异。
- 证据包清单 22 项、快照清单 252 项均匹配；外层 SQLite 完整性为 `ok`，8 条记录、8 份凭据、导出与调度锁证明一致。
- 冻结测试报告为 153 项、0 项失败、0 项错误、1 项跳过。
- 快照审核前后均为 253 个文件、2,023,756 字节，整树摘要保持 `c29df0cc4cc4a60efa4dbf985730465c9fb1efdf884c17b5ea61859131d91e08`。

## 保留的独立原始证据

- `C:\Users\yiqun\AppData\Local\Temp\nh_m3r9_recovery_review_20260720_105512_a05faa7e\audit_report.json`
- `C:\Users\yiqun\AppData\Local\Temp\nh_m3r9_recovery_review_20260720_105512_a05faa7e\fresh_targeted_tests.xml`
- 同目录下保留失败测试的 `pytest_tmp`。

审核边界：未读取、寻找或评分最终评估期数据；未运行公平基准评分程序；未执行正式流域搜索；未作超过基线声明。
