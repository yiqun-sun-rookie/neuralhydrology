# 由远到近连续历史状态传递独立对抗审核

**审核对象：** 使用远期、中期和近期气象历史连续传递循环状态、最终只输出一个流量的内部验证实验  
**实验标识：** `E07-S01`  
**审核结论：** `PASS`  
**结论边界：** `PASS` 只表示当前结果链及“第一阶段不继续”的结论经得住本次审核，不表示模型有效，不表示较早气象历史无用，也不表示正式评估性能已知。

## 1. 冻结状态和审核范围

- 审核开始时提交精确为 `183309a1021c41b6722bab9ea968bc1fb3c2c666`，与预期一致；分支为 `codex/historical-band-experts-pilot`，工作区干净。
- 审核发现并复现了重置诊断指标不能从保存预测精确重算的问题。修复提交为 `7af498cd649830811a325b822c1e758c1e5b8bac`，透明记录提交为 `456f5b2f0d069509549e9007bf645cc686882a31`；最终审核以 `456f5b2f0d069509549e9007bf645cc686882a31` 为准。
- 本审核没有运行真实数据训练，没有读取原始观测流量文件，没有读取正式评估观测或答案，也没有修改冻结基准文件。
- 审核者唯一写入是本文件。测试中的微型训练只使用测试构造的合成数据。

## 2. 模型、时间索引和输入边界

### 已确认事实

1. 候选模型有三个单层长短期记忆网络编码器。远期编码器的完整隐藏状态和记忆状态直接初始化中期编码器，中期的完整隐藏状态和记忆状态直接初始化近期编码器。
2. 三个编码器联合进入同一个优化器。保存的首批梯度范数为远期 `549.0861`、中期 `149.9678`、近期 `113.3563`，均为有限非零值。
3. 模型只有一个 `256 → 1` 线性输出头，只从近期编码器最终状态输出一个流量。
4. 每个时间步的模型输入只有 Maurer 的 5 项逐日气象驱动和重复的 27 项静态属性。训练流量只作为监督目标，没有进入模型输入。
5. 三段索引为：
   - 远期：滞后 `1825–3649` 天，共 `1825` 天，压缩为 60 个按时间正序排列的均值块；
   - 中期：滞后 `270–1824` 天，共 `1555` 天，压缩为 60 个按时间正序排列的均值块；
   - 近期：滞后 `0–269` 天，共 270 个逐日时间步。
6. 独立构造索引得到 3650 个时间位置、3650 个唯一位置、缺失 0、重叠 0、未来位置 0。最早到最晚的位置连续为目标索引减 `3649` 至目标索引本身。
7. 四个主比较预测文件都包含 60 个流域、每个流域 731 天、合计 43,860 行，日期严格为 `2006-10-01` 至 `2008-09-30`；重复流域—日期键为 0，键和观测值逐行完全一致。

### 正式评估边界的精确定义

内部目标包只有 `1999-10-01` 至 `2008-09-30`，其清单记录正式评估行数为 0。候选数据加载路径没有原始观测流量加载器，也没有 `usgs_streamflow`、`camels_hydro` 或正式评估答案文件引用。

由于模型使用 3650 天气象历史，首个训练目标 `1999-10-01` 的 Maurer 气象输入从 `1989-10-04` 开始，日历上与正式评估目标期重叠。因此，清单中的“正式评估访问为 false”只能解释为“没有读取正式评估观测、答案或生成正式评估预测”，不能解释为“没有读取该日历区间的气象驱动”。这与批准设计中的因果历史输入一致。

## 3. 公平性和训练协议

| 模型 | 独立检查的参数量 |
|---|---:|
| 经典近期模型，隐藏宽度 256 | 297,217 |
| 参数量控制，隐藏宽度 455 | 890,436 |
| 连续状态传递候选 | 891,137 |

- 候选比参数量控制多 701 个参数，相对候选为 `0.0787%`，低于预注册的 `1%` 上限。
- 三个检查点的参数张量元素总数分别与上述数值完全一致。候选检查点只有三个编码器的 12 个循环参数张量和一个输出头的 2 个参数张量。
- 候选的近期编码器和输出头在训练前从同训练随机数的经典近期模型复制。源码和测试共同确认二者逐位相同。
- 三个完整运行都有 153,420 个训练坐标、30 轮、每轮 600 次更新、合计 18,000 次更新、43,860 条验证预测；学习率变更、损失权重、梯度裁剪和最终轮检查点协议一致。
- 近期宽度 256 和宽度 455 两个控制的预测 SHA-256 分别与先前冻结控制完全相同。
- 训练循环在完成 30 轮后才计算验证预测，没有按验证指标选择检查点。

没有发现未来信息、样本错位、分段空缺或重叠、流量输入、参数量门槛违规，或训练协议不公平到足以推翻当前比较的问题。

## 4. 四个主比较的独立重算

纳什－萨特克利夫效率系数由本审核直接按
`1 − 误差平方和 / 观测离均差平方和`
计算，没有导入本项目分析器或指标模块。

| 模型 | 60 流域中位纳什－萨特克利夫效率系数 |
|---|---:|
| 经典近期模型 | 0.682708709251 |
| 参数量控制 | 0.708129838031 |
| 已有简单历史后期拼接 | 0.695811909868 |
| 连续状态传递候选 | 0.679955186119 |

| 预注册门槛 | 独立重算 | 阈值 | 结果 |
|---|---:|---:|---|
| 候选相对经典近期模型的逐流域差值中位数 | +0.001397600959 | ≥ +0.01 | 不通过 |
| 候选相对参数量控制的逐流域差值中位数 | −0.007734539708 | > 0 | 不通过 |
| 候选相对简单历史拼接的逐流域差值中位数 | −0.005646797671 | > 0 | 不通过 |
| 候选相对经典近期模型的胜出流域 | 32/60，即 53.3333% | ≥ 55% | 不通过 |

候选相对经典近期模型为 32 胜、28 负、0 平。最接近 0 的负差值仍为 `−0.0094915`，所以胜出数不会因文件精度或末位舍入从 32 变成 33。四项门槛全部失败的结论得到独立重算支持。

## 5. 重置诊断和解释边界

修复后的四种模式各有 43,860 条预测，键和观测值完全一致。按保存预测独立重算、再按保存指标声明的 12 位有效数字表示后，四个逐流域指标文件逐位一致。

| 模式 | 中位纳什－萨特克利夫效率系数 | 相对完整连接的逐流域差值中位数 |
|---|---:|---:|
| 完整连接 | 0.679955186119 | 0 |
| 切断远期到中期 | 0.670121663471 | −0.004741412215 |
| 切断中期到近期 | 0.647700503856 | −0.015095818426 |
| 两处均切断 | 0.647700503856 | −0.015095818426 |

附加一致性检查：

- 完整连接预测与主候选预测逐行、逐值完全相同；
- “切断中期到近期”和“两处均切断”预测完全相同，这是因为中期到近期被切断后，远期和中期状态都无法影响唯一输出；
- “两处均切断”不等于单独训练的经典近期模型。它只是共同训练后候选模型的近期路径；其逐流域效率相对经典近期模型的差值中位数为 `−0.0393199`。

因此，重置下降只能证明训练完成的候选依赖状态连接。共同训练已经改变近期参数，且重置改变了模型预期的状态分布；这些差值不能解释为远期或中期历史的因果贡献。

## 6. 审核发现的问题及修复复核

### 已修复问题

最初的重置诊断先从写盘前数组计算指标，再写入预测。审核从保存预测重算时，逐流域指标最大绝对差为 `4.03684×10⁻⁵`，四种模式中位数的最大变化为 `1.075×10⁻⁸`。根因是指标与证据文件没有使用同一个写盘后数值源。

提交 `7af498cd649830811a325b822c1e758c1e5b8bac` 改为先保存并重新读取预测，再计算指标。修复后：

- 四个预测文件 SHA-256 与修复前完全相同；
- 四个指标文件都能由对应保存预测逐位重算；
- 当前重置摘要与根目录摘要内嵌内容完全一致；
- 修复前目录 `reset_diagnostics_s100_pre_recompute_fix_20260727` 保留，未被当前根摘要或分析清单引用；
- 修复前清单 SHA-256 为 `e0d4e25a27b4a947118d094b28bc3cb748d55a85b97ca78962f8bc50b521fffb`。

该问题不改变六位小数结果、任何主比较门槛或第一阶段停止决定。

## 7. 产物哈希、停止条件和访问记录

- 当前活动结果共有 5 份清单，声明 26 个产物 SHA-256；独立重算结果为 `26/26` 匹配。
- 另外核验了流域列表、内部目标包、严格嵌套摘要、单训练随机数历史参照和多训练随机数历史参照的 5 个冻结 SHA-256，结果为 `5/5` 匹配。
- 当前 5 份活动清单本身的 SHA-256 为：

| 清单 | SHA-256 |
|---|---|
| 经典近期模型运行清单 | `44ed1eaf19d4755b6474a0fa6a82ac54c784a54a5eceee04c0c18a11ec58e06c` |
| 参数量控制运行清单 | `9c47b86eff3fdfecfd1109515fa7e20308f068c0fc2aca4cb06f89a800b2609b` |
| 连续状态传递候选运行清单 | `6de8778c7e3db00b59f105a0d9a90f5dc3f1fa275ddb5e7f251b79140ca2bccf` |
| 修复后重置诊断清单 | `e73cbce7ee3b9371291ac7caaaa5174722dec3eb28cd8b0624bfca27afbbdf63` |
| 根分析清单 | `fe20b913a764ca6c03b9a4ca30fa40c1e4f61b79f45392114067c39509016946` |

- 三个训练运行、重置诊断和根分析清单均记录原始观测流量读取为 0、正式评估访问为 `false`。
- 第一阶段失败后，活动结果根和全部实验标识为 `E07-S01` 的结果中均没有训练随机数 200 或 300 的完整运行目录；根摘要要求的后续训练随机数为空。
- 正式评估观测和答案没有进入内部目标包，活动预测日期没有进入正式评估期。

结果目录受 `.gitignore` 的 `results/**` 规则排除，产物本身不在 Git 提交中。本报告记录活动清单 SHA-256 后可以检测后续变化，但长期可审核性仍依赖本地结果目录被完整保留。

## 8. 测试和实际执行的关键命令

最终提交 `456f5b2f0d069509549e9007bf645cc686882a31` 上执行：

```powershell
git rev-parse HEAD
git branch --show-current
git status --short
git log -3 --format='%H %ad %s' --date=iso-strict
git diff --check
```

```powershell
$env:PYTHONDONTWRITEBYTECODE='1'
pytest -q -p no:cacheprovider src/26_historical_band_experts/tests/test_sequential_transfer_v07.py
pytest -q -p no:cacheprovider src/26_historical_band_experts/tests
```

结果分别为 `20 passed, 1 warning` 和 `308 passed, 1 warning`。唯一警告是当前环境不认识 pytest 配置项 `collect_ignore_glob`，没有测试失败。

输入和禁止路径检查使用：

```powershell
rg -n -i "usgs_streamflow|camels_hydro|obs_eval|answer.key|formal.eval|forbidden" `
  src/26_historical_band_experts/models_sequential_v07.py `
  src/26_historical_band_experts/train_sequential_v07.py `
  src/26_historical_band_experts/analyze_sequential_v07.py `
  src/26_historical_band_experts/data.py `
  src/26_historical_band_experts/bands_v03.py `
  src/26_historical_band_experts/configs/sequential_transfer_s01_v07.json

Get-ChildItem results/26_historical_band_experts/sequential_coarse_to_fine_v07 -Directory
git ls-files "results/26_historical_band_experts/sequential_coarse_to_fine_v07/**"
git check-ignore -v results/26_historical_band_experts/sequential_coarse_to_fine_v07/analysis_manifest.json
```

独立指标与哈希重算使用 pandas、NumPy 和 Python 标准库直接读取预测及清单。核心公式和清单循环如下，没有导入项目分析器或指标模块：

```powershell
@'
from pathlib import Path
import hashlib, json
import numpy as np
import pandas as pd

repo = Path.cwd()
root = repo / "results/26_historical_band_experts/sequential_coarse_to_fine_v07"

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1048576), b""):
            digest.update(block)
    return digest.hexdigest()

def load(path):
    frame = pd.read_csv(path, dtype={"basin": str})
    return frame.sort_values(["basin", "date"]).reset_index(drop=True)

def per_basin(frame):
    rows = []
    for basin, group in frame.groupby("basin", sort=True):
        observed = group["qobs"].to_numpy(np.float64)
        simulated = group["qsim"].to_numpy(np.float64)
        value = 1 - np.square(simulated - observed).sum() / np.square(
            observed - observed.mean()
        ).sum()
        rows.append((basin, value, float(f"{value:.12g}"), len(group)))
    return pd.DataFrame(rows, columns=["basin", "raw", "nse", "n_days"])

paths = {
    "classic": root / "classic_lstm_256_keyed_s100/predictions.csv",
    "capacity": root / "classic_lstm_455_keyed_s100/predictions.csv",
    "late_concat": repo / (
        "results/26_historical_band_experts/classic_lstm_historical_context_v03/"
        "late_concat_s100/predictions.csv"
    ),
    "candidate": root / "sequential_transfer_s100/predictions.csv",
}
predictions = {name: load(path) for name, path in paths.items()}
metrics = {name: per_basin(frame) for name, frame in predictions.items()}

for mode in ("none", "old_to_medium", "medium_to_recent", "both"):
    frame = load(root / f"reset_diagnostics_s100/{mode}_predictions.csv")
    saved = pd.read_csv(
        root / f"reset_diagnostics_s100/{mode}_per_basin_metrics.csv",
        dtype={"basin": str},
    ).sort_values("basin").reset_index(drop=True)
    assert saved[["basin", "nse", "n_days"]].equals(
        per_basin(frame)[["basin", "nse", "n_days"]]
    )

manifests = [
    root / "classic_lstm_256_keyed_s100/manifest.json",
    root / "classic_lstm_455_keyed_s100/manifest.json",
    root / "sequential_transfer_s100/manifest.json",
    root / "reset_diagnostics_s100/manifest.json",
    root / "analysis_manifest.json",
]
for manifest_path in manifests:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for name, expected in manifest["artifacts"].items():
        assert sha256(manifest_path.parent / name) == expected
'@ | python -
```

## 9. 无法独立证明的内容

1. 清单中的原始观测流量读取次数和正式评估访问标记由程序写入，不是操作系统级文件访问遥测。本审核能证明候选源码路径、目标包边界和现有产物没有违规证据，不能证明进程在操作系统层面从未打开其他文件。
2. 运行清单没有完整冻结 Python、PyTorch、CUDA、驱动和硬件版本，因此当前链条可审核，但不能保证未来逐位重跑。
3. 只有训练随机数 100。由于四项第一阶段门槛均失败，停止 200 和 300 符合预注册协议；同时也意味着无法判断跨训练随机数稳定性。
4. 没有打开 531 流域正式评估，因此正式泛化性能目前无法确定。

## 10. 最终判断

| 审核问题 | 判断 |
|---|---|
| 模型是否真实执行远期完整状态→中期→近期、联合训练和唯一流量输出 | 通过 |
| 是否发现未来信息、样本错位、分段空缺或重叠、禁止模型输入 | 未发现 |
| 参数量和训练协议是否满足预注册公平约束 | 通过 |
| 四个主比较能否从保存预测独立重算 | 通过 |
| 修复后的四个重置指标能否从保存预测逐位重算 | 通过 |
| 26 个活动产物 SHA-256 是否全部匹配 | 通过，26/26 |
| 训练随机数 200、300 是否在第一阶段失败后停止 | 通过，当前证据中没有对应运行 |
| 能否把重置下降解释为历史状态的因果贡献 | 不能 |
| 能否声称候选模型有效或稳定优于对照 | 不能 |
| “第一阶段不继续、不进入正式评估”的结论是否经得住审核 | 通过 |

**最终结论：`PASS`。** 当前最窄且可验证的结论是：在冻结的 60 流域、三段历史表示和训练协议下，连续状态传递候选只相对经典近期模型产生 `+0.0013976` 的逐流域差值中位数，且弱于参数量控制和已有简单历史拼接；四项预注册门槛全部失败，因此停止训练随机数 200、300 并不进入正式评估是正确决定。
