# 里程碑一第三修复版预审核失败记录

- 证据根：`5ad8264fb7abbb6be0aacc14f7eb20462b2f5e9d64870ec66cbc4a2f0bdb2969`
- 只读快照：`runs/unified_autoresearch_audits/m1_repair3_5ad8264fb7abbb6b_clean`
- 判定：**未进入独立审核**。

主任务从快照使用独立、较长的系统临时 `basetemp` 重跑 36 项测试时，35 项通过、1 项失败。
失败发生在深运行根清单回归测试自身：生产函数已经用长路径安全接口生成 `PACKAGE_MANIFEST.sha256`，
但测试随后用普通 `Path.read_text()` 读取该深路径文件，触发 `FileNotFoundError`。

该失败是预审核门槛直接得到的事实，因此第三修复版不交给独立审核，也不覆盖。测试读取改为独立的 Windows 长路径安全读取后，
相同长系统临时根下 36 项通过、0 项失败；下一次证据生成使用新的第四修复版根。
