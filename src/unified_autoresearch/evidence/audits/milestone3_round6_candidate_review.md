# 第三里程碑第六轮四类参考候选独立审核

审核结论：`FAIL`

冻结快照不满足里程碑三第六轮功能准入，存在两个结论性问题。

## 四类候选无法全部从指定快照运行

概念降雨径流候选源文件的绝对路径长 268 个字符。文件物理存在且散列正确，但活动 Python 3.11.5 使用普通路径时，
`Path.exists()` 返回 `False`，`Path.read_bytes()` 抛出 `FileNotFoundError`。从冻结快照直接运行完整测试得到
148 项通过、2 项失败、1 项跳过；两项失败分别是该候选的物化测试及训练和预测统一登记入口测试。

最小复现：

```powershell
python -I -B -c "import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(len(str(p)),p.exists()); p.read_bytes()" "G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\runs\unified_autoresearch_audits\milestone3_round6_reference_candidates_repair1_184dd693501710c7_clean\src\unified_autoresearch\candidates\implementations\conceptual_rainfall_runoff.py"
```

确定性结果为 `268 False`，随后退出状态 1 和 `FileNotFoundError`。

## 声明依赖初始化边界没有被完整证明

访问记录确实先于声明依赖导入启用，但当前回归测试把声明依赖源码根本身排除在允许读取根之外，因此读取依赖源码时已经拒绝，
没有验证“允许读取依赖源码之后，其初始化再读取声明根之外的良性文本必须拒绝”。运行策略还把整个标准库根作为读取根；当前
Windows 环境中该根包含全部 `site-packages`，没有独立的声明依赖源码根边界。因此核心命题不能准入。

## 原始证据复核

- 活动版本精确为 NumPy 1.26.4、pandas 2.3.3、PyArrow 22.0.0。
- 八部分根散列重算为 `184dd693501710c739cd80b2d4e4028efa21a395ae2d3cd0ce0a5c61c89d9d02`，与记录一致。
- 实际引用 232 项、118 个唯一文件，全部字节和散列一致。
- 快照清单 134 项、运行包清单 22 项，均无遗漏、额外项或字节不符。
- Git 差异原始文件为 0 字节；Git 状态原始文件为 7160 字节；两者散列均匹配。
- SQLite 完整性为 `ok`；8 条记录的散列链、状态链、导出和 8 份凭据一致，最终状态为 `succeeded`。
- 冻结结构化测试报告记录 151 项测试、0 项失败、0 项错误、1 项跳过；该报告不能覆盖从当前长路径快照直接运行的失败。
- 复验前后快照均为 135 个文件、21 个目录、0 个链接；整树清单散列同为
  `d5f1f8248533870f44691f3421310c3a7762b9cd499416b20fcf200ae5d371cd`。

审核材料保留在
`C:\Users\yiqun\AppData\Local\Temp\milestone3_round6_functional_review_d64869f563b547969e4f87089decfbb2`。

边界：未读取、寻找或评分最终评估数据，未运行公平基准评分程序，未执行正式流域搜索，未作超过基线声明。
