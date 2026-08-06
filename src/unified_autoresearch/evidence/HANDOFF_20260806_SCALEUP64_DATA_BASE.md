# 交接:自动科研纵向 · 里程碑四已收口 → 下一步建 64 流域数据底座

写于里程碑四收口并首次提交之后。本文自包含,新对话只读本文即可续接。

## 一、总目标与当前阶段定位

**总目标**:建一条自动化科研流水线("统一自动科研纵向"),能自动提出并**安全**评估水文模型候选:
隔离运行、独立资源监督、可复现打分、防作弊双重复核,最终扩到 64 → 531 个 CAMELS-US 流域做正式候选搜索。
目前为止**零科研产出,全部是基础设施**——流水线里的 4 个"参考候选"是占位极简模型,只为证明流程与安全闸门有效。

**当前阶段**:里程碑 0–4 全部完成(隔离运行时→登记→开发循环→真实数据→独立监督),已首次提交进 git。
下一阶段 = 扩规模第一格:**冻结 64 流域选择并构建真实开发数据源与两协议数据包**(即
`MILESTONE4_SCALEUP_CHECKLIST_64_531.md` §四第 1–4 条)。这一步不需要新决定,是唯一可直接动手的活;
做完才轮到需要用户拍板的并行度与聚合资源门槛设计(同文 §五)。

## 二、必须遵守的红线(全部仍然有效)

1. 禁止读取/枚举/打分封存的最终评估数据(1989-10-01 至 1999-09-30)。
2. 禁止运行 `src/fair_benchmark/score.py`。
3. 禁止跑 64/531 流域**正式搜索**(建数据底座不属于正式搜索,允许)。
4. 禁止宣称任何候选超过任何基线。
5. 候选预测只能用气象强迫 + 静态属性,禁止用观测流量/真值。
6. 禁止清理/重置/覆盖/暂存/提交用户的改动;**任何 git 提交需用户明确授权**。
7. 里程碑收口必须双重独立复核:一个功能对抗式审核上下文 + 一个从原始字节复验的上下文,互不通气。
8. 一切改动测试先行(先写红测试再实现)。同一任务失败 5 次必须停下问人。
9. 污染/异常产物不清理、不覆盖,留作证据(如 `supervised_development_loop_real_v1/_v2`)。

**8 个冻结开发流域**:10259000 04045500 12175500 02300700 08190500 02038850 11230500 06847900。
**流量单位换算**:`28316846.592 × flow(cfs) × 86400 ÷ (area_m2 × 10^6)`(最大坑,逐流域核查项)。

## 三、已完成与关键结论(全部有证据支撑)

- **测试基线**:185 通过 / 5 跳过 / 0 失败。5 跳过 = 软链接逃逸反向测试,因本机无创建软链接权限
  (WinError 1314)跳过;对应修复代码已确认存在于 `runtime/layout.py` 与 `evaluation/scoring.py`,
  但**未在本机跑绿(未验证)**,须在开发者模式/管理员环境补跑。
- **停机策略 v3(按任务相对判断)**:候选自身内存超"声明包络×1.5"(包络 = estimated_peak_memory_gb +
  memory_safety_reserve_gb)才停;系统内存仅在可用 < 1.5 GB 或 < 总量 4% 时停;磁盘 < 10 GB 立即停。
  冻结的 v1 未动,运行器已指向 v3。
- **v3 修复了真实误停**:旧 v1 的绝对 4 GB 下限落在本机(31.7 GB 总内存)正常波动带内,曾把只占
  0.026 GB 的候选误停(系统内存 4.02→3.953→3.727 GB,连续两次跌破 4 GB,退出码 75)。v3 下重跑,
  r2 系统内存最低探到 2.87 GB(低于旧下限)未停且完整跑通——修复在真实数据上自证。
- **两次监督完整循环**(`supervised_development_loop_v3_r1`/`_r2`):各 16 个已登记运行全过五项门槛、
  0 受控停止、全程受监督;两次的科学子集(8 评分 + 4 汇总 = 12 文件)逐字节一致(sha256 逐一相同)。
- **峰值估算已冻结校准**:实测进程峰值 0.1376 / 0.1367 GB vs 声明 0.60 GB,保守约 4.36 倍。
- **双重独立复核完成**:原始字节复验 = CONFIRMED_PASS(九项自算全对上);功能对抗审核 = PASS(有保留),
  挑出 3 处弱点已全部测试先行修掉:
  - F1:未声明内存预算时候选自占用刹车默认失效——已补测试钉死其退化为"仅系统级监督",绝非无监督。
  - F2:循环自报的四个安全标记是硬编码自证——校验器改为从每个运行原始 `logs/access.jsonl` 独立复算
    禁止访问数(`decision=="deny"` 计数),通过门槛只认独立复算值,自报标记降级为仅存档;schema 升 v2。
  - F3:监督身份发布未锁严格 JSON——无穷大预算改序列化为 `null`(读回还原为无穷大),加 `allow_nan=False`。
  - F4–F7 为文案/浮点/已自认设计边界,不影响事实,未改(详见证据文档 §六)。
- **强化门槛真实数据复验**:独立复算禁止访问数在全 32 运行 = 0、与自报一致,
  `milestone_four_run_gate_passed = true`,落于
  `runs/unified_autoresearch/supervised_development_loop_v3_r1/VERIFICATION_INDEPENDENT_GATE.json`
  (新文件;冻结的旧 `VERIFICATION.json` 未覆盖)。
- **已提交**:commit `81974588`(144 文件,`src/unified_autoresearch/` 首次入库),工作树干净。

## 四、位置与关键路径

- **工作副本**(不是 kalmannet 主仓库):`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical`
  分支 `codex/unified-autoresearch-vertical`。以下相对路径均以此为根。
- 代码包:`src/unified_autoresearch/`;测试:`src/unified_autoresearch/tests/`(pytest,全量约 9 分钟)。
- 策略:`src/unified_autoresearch/protocols/resource_safety_v1.json`(冻结勿动)、`resource_safety_v3.json`(现行)。
- 监督:`src/unified_autoresearch/runtime/monitor.py`;运行器:`runtime/runner.py`;
  循环:`workflow/development_loop.py`;校验器:`scripts/verify_supervised_real_loops.py`(schema v2)。
- 数据构建脚本(下一步的主角):`src/unified_autoresearch/data/real_source.py`、`data/packages.py`、
  `scripts/build_real_development_source.py`、`scripts/build_real_development_packages.py`。
- 流域选择:`src/unified_autoresearch/selection/basins.py`、`selection/development_basins_v1.json`(8 流域冻结版)。
- 证据:`src/unified_autoresearch/evidence/PROGRESS.md`(逐阶段总账)、
  `MILESTONE4_SUPERVISED_LOOPS_V3_20260725.md`(里程碑四全记录含 §六复核)、
  `MILESTONE4_SCALEUP_CHECKLIST_64_531.md`(扩规模清单=下一步任务书)、
  `HANDOFF_20260724_REALDATA_AND_MONITOR.md`(上一份交接,含红线原文)。
- 运行产物:`runs/unified_autoresearch/`(被 .gitignore 忽略,不入库)。其中 `..._real_v1/_v2` 为旧策略
  标定证据(v2 含真实误停记录),`..._v3_r1/_r2` 为冻结的达标产物——都不许清理或覆盖。
- 8 流域真实数据源根与数据包的具体落盘路径:**未验证**,从 `scripts/run_real_development_loop.py` 的
  调用参数或各 LOOP_SUMMARY.json 的 package manifest 字段追溯。

## 五、已确认/已排除的问题

- **已排除**:分支上 2026-07-02~07-13 的一批论文手稿提交(HEAD 前几条,如 `ffbde6d9`)属另一条无关
  工作线,经 `git log --stat` 核实无一触碰 `unified_autoresearch`;`src/unified_autoresearch/` 内所有文件
  修改时间均对应本工作线会话,无并行会话篡改。
- **已确认的坑**:① `tee | tail` 管道会吞掉 python 真实退出码——判断循环成败一律查 LOOP_SUMMARY.json
  是否存在,别信管道退出码。② 本机时钟/日期标签不一致(文件时间戳、提交时间、会话日期互相对不上)——
  判断新旧一律以 git 哈希为准,别用日期。③ pandoc/论文线的东西与本线无关,别混。
- **敏感流域**(扩 64 时判定规则不能只看中位数):06847900(验证期流量标准差极小)、
  08190500(大量零流量日)。

## 六、未完成事项与阻塞

| 事项 | 状态/阻塞 |
|---|---|
| 64 流域数据底座(下一步,最优先) | 未开始,无阻塞,可直接动手 |
| 5 条软链接测试补跑 | 阻塞于环境:需用户开 Windows 开发者模式或管理员权限,用户开好后跑全量测试,预期 190 通过 / 0 跳过 |
| 推送远程 | 阻塞于用户拍板:分支无 upstream;推送会连带那批无关论文提交 |
| 并行度与聚合资源门槛设计 | 阻塞于用户拍板(见扩规模清单 §五) |
| 汇总间隔 summary_interval_seconds | 协议里有、未实现 |
| 重任务/长时/图形处理器/并行下的监督行为 | 未验证(演示候选峰值仅约 0.14 GB、单次数秒) |

## 七、下一步任务书(64 流域数据底座,测试先行)

1. 冻结 64 流域选择:从 531 个 CAMELS-US 流域按**确定性、可复现**规则选出 64 个(须含 8 个已冻结
   开发流域还是与之互斥——先读 `selection/basins.py` 里 8 流域的选法与注释再定,拿不准问用户);
   落成新冻结文件(如 `selection/development_basins_64_v1.json`),散列钉死。
2. 用 `data/real_source.py` / `data/packages.py` 为 64 流域构建真实开发数据源与 forward/reverse 两协议数据包。
3. 逐流域核查(写成测试):日期边界正确;封存区间(1989-10-01~1999-09-30)命中 0;预测包不含观测流量;
   单位换算(见 §二)无误;27 项静态属性无缺失;全部散列钉死。
4. 两个敏感流域(06847900、08190500)单独写核查用例。
5. 全量测试回归(预期 ≥185 通过 / 5 跳过 / 0 失败,新增测试另计);证据落 `evidence/`;
   提交前必须先问用户。

## 八、新对话开场自检(先跑再干活)

```bash
cd "G:/github/pycharm/projects/neuralhydrology/.worktrees/unified-autoresearch-vertical"
git log -1 --format="%h %s"        # 应为 81974588 feat(autoresearch): ...
git status --porcelain             # 应为空(除你自己新建的文件)
python -m pytest src/unified_autoresearch/tests -q   # 应 185 passed, 5 skipped(约 9 分钟)
```

先读的文件(按序):本文 → `evidence/MILESTONE4_SCALEUP_CHECKLIST_64_531.md` →
`selection/basins.py` + `selection/development_basins_v1.json` → `data/real_source.py`。
若自检任一不符,先停下向用户报告差异,不要动手改。
