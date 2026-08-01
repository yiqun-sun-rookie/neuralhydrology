# 里程碑二受限候选运行环境实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for every executable behavior.

**目标：** 建立可验证的统一 Python 候选协议和受限运行环境，不使用最终评估数据或正式训练。

**架构：** 严格候选描述产生排他隔离目录，固定启动器在候选代码前安装默认拒绝审核钩子；父进程验证退出状态、
访问日志和候选暂存检查点，并把有效检查点原子提升为不可覆盖版本。

**技术：** Python 标准库、SQLite 登记、pytest、256 位安全散列。

---

### 任务一：候选描述和隔离目录

**文件：**
- 新建 `src/unified_autoresearch/runtime/descriptor.py`
- 新建 `src/unified_autoresearch/runtime/layout.py`
- 新建 `src/unified_autoresearch/tests/test_runtime_descriptor.py`

1. 写缺失入口、未知字段、非精确依赖版本和越界路径失败测试，确认因功能缺失而失败。
2. 实现严格描述校验并确认定向测试通过。
3. 写已存在运行根、输入输出别名和预测真值挂载失败测试，确认失败。
4. 实现排他目录构建和预测输入白名单并确认完整测试通过。

### 任务二：固定命令适配器和运行时限制

**文件：**
- 新建 `src/unified_autoresearch/runtime/adapter.py`
- 新建 `src/unified_autoresearch/runtime/bootstrap.py`
- 新建 `src/unified_autoresearch/runtime/runner.py`
- 新建 `src/unified_autoresearch/tests/test_restricted_runtime.py`

1. 写真实文件打开反例：允许文件读取成功，清单外文件读取失败并留下拒绝记录。
2. 实现固定启动器、预开访问日志和文件审核钩子，确认测试通过。
3. 分别写未声明依赖、子进程、网络和动态本地库反例，逐项确认失败。
4. 实现最小拒绝规则，逐项确认定向测试和完整测试通过。
5. 写未知退出状态和输出越界失败测试，实现结构化运行结果校验。

### 任务三：受控停止、原子检查点和恢复

**文件：**
- 新建 `src/unified_autoresearch/runtime/checkpoints.py`
- 修改 `src/unified_autoresearch/runtime/runner.py`
- 新建 `src/unified_autoresearch/tests/test_runtime_checkpoints.py`

1. 写非原子最终路径写入、缺少清单和重复检查点版本失败测试。
2. 实现暂存检查点验证、文件散列清单和同卷原子提升。
3. 写退出状态 75 但无有效检查点的失败测试，再实现受控停止结果校验。
4. 写恢复引用缺失、散列不一致和有效恢复测试，再实现只读恢复挂载。
5. 运行全部里程碑测试。

### 任务四：不可覆盖证据和双独立审核

**文件：**
- 新建一个 `runs/unified_autoresearch/milestone2_round1/` 证据根
- 新建根散列一致的只读审核快照
- 更新 `src/unified_autoresearch/evidence/PROGRESS.md`

1. 记录测试命令、标准输出、标准错误、资源估计、版本控制差异和状态原始字节。
2. 以真实调度锁和外部登记凭据追加候选、实验、状态和完整数字指纹。
3. 重算两级文件清单，建立操作系统拒写的干净快照并从快照重跑测试。
4. 由两个全新独立任务分别完整审核和定向复验；任一失败都先产生失败测试并使用新证据根修复。

