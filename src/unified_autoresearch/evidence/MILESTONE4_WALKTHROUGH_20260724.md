# 里程碑四：资源监督流程走通（2026-07-24，缩减范围）

## 结论

独立资源监督进程已实现并在真实数据上跑通一条完整链路：监督先于候选启动、按四项归属字段核验、
按任务间隔采样、原子追加资源日志、越限时写出冻结格式的受控停止请求。冻结测试 **180 项通过、0 跳过、0 失败**。

本轮按“不跑全部，只跑通流程”执行：真实演示只做 **1 类候选 × 1 套协议**，不是四类两协议的完整循环，
里程碑四并未完成。未完成项见第五节。本文件不宣称任何候选超过任何基线。

## 一、新增实现

- `runtime/monitor.py`：独立监督进程。
  - `verify_process_ownership`：进程号、创建时间、可执行文件路径、运行标识四项全部一致才承认归属。
  - `evaluate_stop_reason`：磁盘低于停写下限立即触发；系统内存需连续两次低于下限才触发（取自冻结协议）。
  - `append_resource_sample`：单次 `os.write` 写入一条完整 JSON 行并 `fsync`，不重写任何既有字节。
  - `supervise`：核验归属 → 采样 → 追加 → 判定 → 越限则写受控停止请求。
  - `publish_monitor_target` / `await_monitor_target`：**监督先启动**，再由运行器公布候选归属身份。
- `runtime/runner.py`：`independent_monitor_enabled` 为真时，先启动监督进程，失败则直接拒绝，
  候选**根本不会被创建**；新增按任务配置的采样间隔参数。
- `runtime/orchestrator.py`：把采样间隔透传到运行器。
- `scripts/run_supervised_real_walkthrough.py`：缩减版真实演示（训练 + 预测 + 评分）。
- `tests/test_resource_monitor.py`：10 项测试，全部先失败后实现。

## 二、被替换的旧规则

`test_restricted_runtime_refuses_declared_monitor_need_until_monitor_is_active` 断言的是
“监督尚未实现，因此声明需要监督的候选一律拒绝运行”。监督实现后该规则失效，已改写为
`test_restricted_runtime_publishes_process_ownership_when_a_monitor_is_declared`，
断言新契约：声明需要监督的候选在监督下正常运行，并在控制目录留下四项归属身份。
原规则中仍然有效的部分（监督起不来就不许启动候选）由
`test_supervised_candidate_refuses_to_launch_when_the_monitor_cannot_start` 承担，
并额外断言候选确实没跑：无访问日志、标准输出为空、无输出产物。

## 三、真实数据上的缩减演示

产物根：`runs/unified_autoresearch/supervised_walkthrough_real_v1`，
数据包：`runs/unified_autoresearch/development_packages_real_v1`，
候选类别 `conceptual_rainfall_runoff`，协议 `forward`，采样间隔 0.25 秒。

| 项 | 训练 | 预测 |
|---|---|---|
| 运行状态 | succeeded | succeeded |
| 采样条数 | 15 | 20 |
| 采样序号连续 | 是 | 是 |
| 实测进程峰值内存 | 0.117 吉字节 | 0.099 吉字节 |
| 采样期最低系统可用内存 | 7.11 吉字节 | 6.82 吉字节 |
| 采样期最低可用磁盘 | 2158.14 吉字节 | 2158.14 吉字节 |
| 受控停止请求 | 未触发 | 未触发 |

评分：8 个流域、8,768 行，`baseline_outperformance_claimed` 与
`sealed_final_evaluation_read_or_scored` 均为 `false`。

**第一次把“声明值”和“实测值”对上了**：候选声明峰值内存 0.35 吉字节加安全余量 0.25 吉字节，
实测峰值 0.117 吉字节，声明保守约三倍。这是后续冻结峰值估算方法的第一个真实标定点。

## 四、受控停止路径的验证方式

真实演示中资源充裕，停止条件未触发。停止路径由测试
`test_monitor_writes_the_frozen_controlled_stop_request_when_a_limit_trips` 验证：
用一份把磁盘下限调高的临时策略，监督在真实子进程上触发并写出
`STOP_REQUEST.json`（`controlled_stop_request_v1`）。**未修改冻结的
`protocols/resource_safety_v1.json`**。因此“越限真的会停真实候选”这一条只有测试证据，没有真实运行证据。

## 五、里程碑四仍未完成的部分

1. **峰值估算方法未冻结**（计划第 1 条）。目前仍是人工声明值，只有一个真实标定点。
2. **未做两次连续完整纵向运行**（计划第 4 条）。本轮只跑 1 类候选 × 1 套协议。
3. **未产出扩展至 64 与 531 流域的时间、存储、并行和数据准备剩余清单**（计划第 5 条）。
4. **未做两个独立上下文的审核与定向复验**（计划第 6 条）。
5. **真实训练规模的重任务仍未验证**。演示候选峰值约 0.1 吉字节、单次数秒；
   图形处理器任务、长时任务、并行任务都没跑过，监督在这些场景下的行为未知。
6. 汇总间隔（协议中的 `summary_interval_seconds`）尚未实现，只实现了采样间隔。
