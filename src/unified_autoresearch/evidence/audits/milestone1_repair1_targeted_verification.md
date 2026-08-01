# 里程碑一修复版定向独立复验

- 独立任务：`/root/milestone1_repair1_targeted_verification`
- 只读快照：`runs/unified_autoresearch_audits/m1_repair1_4b37af50abb0a1d1_clean`
- 判定：**CONFIRMED**。

## 原始证据

- Windows 长路径安全枚举得到 62 个物理文件；快照清单只有 53 条，正确值应为 61 条；
  缺失集合恰为序号 1 至 8 的 8 个外部登记凭据，多余集合为空。
- 8 个凭据的快照相对路径均为 121 个字符，普通绝对路径均为 272 个字符；文件实际存在，
  字节数和 256 位安全散列均与包含它们的 22 条运行包清单一致。
- 普通 `Path.rglob("*")` 能产生这些路径对象，但 `Path.is_file()` 和 `Path.exists()` 对 272 字符普通路径返回假，
  `Path.stat()` 报 `FileNotFoundError`；带 `\\?\` 前缀的原始枚举和读取全部成功。
- `evidence_package.py` 复制时使用长路径前缀，生成快照清单时却使用普通 `rglob` 后接 `is_file()`，
  处理不一致直接造成“文件存在但未入清单”。
- 重新计算的数字指纹根、`fingerprint.json`、`SNAPSHOT.json` 和目录名前 16 位一致；
  完整根散列为 `4b37af50abb0a1d128dc75b6125faea86da0e2ce5fbc3f49ae5fd9fe2dd707ce`。

## 下一轮检验

在 Windows 深路径中生成快照，先断言至少一个凭据绝对路径超过 260 字符，再要求：

`快照清单路径集合 = 长路径安全枚举的物理文件集合 - 快照清单自身`。

当前实现少 8 项，修复后应为 61 项且差集为空。
