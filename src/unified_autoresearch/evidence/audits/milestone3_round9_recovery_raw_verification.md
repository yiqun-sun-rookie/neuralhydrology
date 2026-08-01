# 第三里程碑第九轮恢复复现原始证据复验

结论：**确认失败**。

两个互相独立的失败均从冻结原始字节复现，不依赖第一层审核结论。

## 一、Windows 260 字符边界失败

- 在全新临时 Git 仓库中，`CHECKPOINT_VERIFIED.json` 完整路径为 259 字符时，普通 `Path.is_file()` 为真，`verify_checkpoint()` 通过。
- 完整路径恰为 260 字符时，同一文件通过 Windows 扩展长度路径可读取，大小 369 字节，SHA-256 为 `132fc97ab791e2e1d8255ddc4c46d19d7ae54434da953e3c124d6495b31b9987`；普通 `Path.is_file()` 为假，普通 `verify_checkpoint()` 报 `checkpoint verified record is missing`。
- 对同一物理路径增加 `\\?\` 前缀后，`Path.is_file()` 和 `verify_checkpoint()` 均通过。
- 当前主机的 `LongPathsEnabled=0`；现有实现没有通过实际 260 字符边界。

## 二、三个历史运行缺少可重放源码字节

- `forward-checkpoint`、`forward-resume`、`forward-clean` 的 `fingerprint.json` 各登记 117 个未跟踪路径，均只有 116 个能从冻结快照按大小和 SHA-256 重放。
- 唯一不一致项均为 `src/unified_autoresearch/evidence/PROGRESS.md`：
  - 历史登记为 23,553 字节，SHA-256 `45448121a72bd71da72c71c331a6e1c49ec0ac6d2366055f30b43a5cccfb775c`；
  - 冻结快照为 24,012 字节，SHA-256 `450c2fd32f8f892dfb170e9c4aa04adf6073481ff5927622068210ca34043c53`。
- 冻结快照全部 253 个文件中不存在历史散列对应字节，也不存在 23,553 字节候选文件。散列不能恢复缺失原始字节，因此三个历史运行的证据链不闭合。

## 其余确认成立的证据

- 三个运行状态依次为 `checkpointed`、`succeeded`、`succeeded`。
- 检查点模型、挂载模型、恢复模型和干净运行模型均为 338 字节，SHA-256 均为 `7bb0dca0335bcf387f46799f6d9e8b6d4ce0345a87ca7708797d0a2f47cb2e64`。
- 发布和挂载检查点的三个文件逐字节相同，检查点根均为 `06a4c8e0684a906d3288c34edc0eac1be5da7a4d98ea2b0a5e86b9630adfeed6`。
- 三个登记数据库各有 8 条记录和 8 份凭据，链错误为 0；调度锁已释放，保存的两份所有权证明一致。
- 三份访问日志分别含 1,220、1,184、1,220 个事件，拒绝、网络和子进程事件均为 0，也没有命中最终评估路径、公平基准评分路径或外部凭据路径。
- 恢复摘要 91 项文件全部匹配。
- 外层八部分根散列为 `271c46ebbd9fdd9c851ae2416c6a3bf0af348a4d02deee3f7cffdc4cce8389e2`；运行包清单 22 项、快照清单 252 项均匹配。
- 冻结测试报告为 152 项通过、1 项跳过、0 项失败；开发输入仅有 8 个流域，日期范围为 1999-10-01 至 2008-09-30。

## 保留的原始证据

证据根：`C:\Users\yiqun\AppData\Local\Temp\m3r9_raw_e29b7b4383c8403685f1f1a4619e6aea\preserved-evidence`

- `FINAL_RAW_VERIFICATION.json`：`3cce986fd4bd23d27f9964158ba4907a258203d68ebbf6ba796ca1032d0e762f`
- `recovery-exact260.junit.xml`：`68005388fea7c36fcc90f25c9f7260b99166eb911f538d545105753de5da8bdc`
- `recovery-length259-pass.junit.xml`：`214986c94546a915a9e520aafde2c26f25458a8fc82209a562e0d55681212dcc`
- `checkpoint-boundary-probe.json`：`6f7c3cc799be5f6e719a4ed5e3012534360cdeb2b5340d38d4cd0481f3ee3af7`
- `historical-untracked-replay.json`：`7499e58589430273984757e5b6d6caeef977341a957e7646c64a1aeb05ab286e`

边界：未读取、寻找或评分最终评估期数据；未运行公平基准评分程序；未执行 64 或 531 流域正式搜索；未作超过基线声明。
