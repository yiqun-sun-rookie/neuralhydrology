# 里程碑一第四修复版审核后污染记录

- 已审核根散列：`945714627daf54dc315ddb37dd0450905254c9c9d526211f694024b7bee71074`
- 已审核快照：`runs/unified_autoresearch_audits/m1_repair4_945714627daf54dc_clean`
- 状态：**双审核发生时通过；审核后准入已撤销**。

两次独立审核完成后，主任务进行最终复核时从快照导入 Python 模块，但该命令没有设置
`PYTHONDONTWRITEBYTECODE=1`。Windows 目录的只读属性不禁止创建新文件，因此 Python 在快照中新增 4 个字节码缓存文件：

- `src/unified_autoresearch/__pycache__/__init__.cpython-311.pyc`
- `src/unified_autoresearch/registry/__pycache__/__init__.cpython-311.pyc`
- `src/unified_autoresearch/registry/__pycache__/fingerprint.cpython-311.pyc`
- `src/unified_autoresearch/registry/__pycache__/store.cpython-311.pyc`

原快照清单没有缺项，但当前物理集合比清单多 4 项。污染发生在两次审核之后，不推翻审核时的原始数值；
它使当前快照不再是干净只读证据，因此不能继续支撑准入。污染文件不删除，快照不覆盖。

下一轮要求操作系统实际拒绝在封存快照中创建新文件，而不仅设置文件和目录的只读属性。
