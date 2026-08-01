# 里程碑二准入结论

## 结论

统一自动研究系统的受限候选运行环境达到准入门槛。后续真实候选必须通过
`runtime.orchestrator.run_registered_candidate` 执行；低层候选执行函数不单独构成已登记运行证据。

## 证据绑定

- 不可覆盖证据根：`runs/unified_autoresearch/milestone2_repair10/`
- 外层数字指纹根：`367edaf567049707152fb7e4b0e21638ea2b8161140a72e327ac082be6b276ae`
- 只读快照：`runs/unified_autoresearch_audits/milestone2_repair10_367edaf567049707_clean/`
- 快照内真实已登记候选探针：`runs/unified_autoresearch/milestone2_repair10_registered_probe/`
- 探针数字指纹根：`ca6d0572ae14c186f0802b53f094f07e98521fb5594d79cfadaa47879f5d7385`
- 第一层完整独立审核：`evidence/audits/milestone2_repair10_full_review.md`，`PASS`
- 第二层原始证据复验：`evidence/audits/milestone2_repair10_raw_verification.md`，`CONFIRMED_PASS`

冻结测试为 109 项：108 项通过、1 项因 Windows 当前账户不能创建符号链接而跳过、0 项失败、0 项错误。
外层登记和凭据为 8/8，运行包为 23/22，快照为 134/133。真实候选探针为 8 条登记、8 份凭据、
5 个状态、1 个最终指纹、1 个输出和 7 个日志；内外两层数字指纹均独立重算一致。

## 准入边界

该结论只准许使用受限候选运行环境开展符合协议的开发候选运行。它不准许读取或寻找
1989-10-01 至 1999-09-30 最终评估数据，不准许运行公平基准评分程序，不准许执行 64 或 531 流域正式搜索，
也不支持任何超过基线的声明。计算资源继续按实际任务需求判断；只有确认不会导致内存崩溃后才可执行，重型任务还必须启用
独立资源监督程序。
