# 迁往 HPC：工作区、环境阻塞、数据底座跨平台重建（2026-08-08）

用户要求把本地机器让出来、尽量用 HPC，并授权机时与 `sbatch`（不再逐次询问）。
本文记录迁移实况：**数据底座已在 HPC 上重建并核查通过；候选运行仍被环境阻塞。**

## 一、HPC 工作区

`~/autoresearch64`，自建 git 仓库（HEAD `67a76d3`，指纹登记需要真实 HEAD）。

**全程未碰**：`~/neuralhydrology`（78 个未提交文件，手册第 7 节禁止）、`~/adv531`（ID05 对抗攻击）、
`nh_final` 环境（迁移前后均为 numpy 2.3.3 / pandas 2.3.2 / pyarrow 20.0.0，实测未变）。
信箱另起 channel `autoresearch-64`，已在 `CHANNELS.md` 登记，未动任何他人 channel。

代码经信箱 channel 传输（335 KB tar.gz，sha256 `b970dcf4…`，收端核对一致），
**未推送代码分支**——那会连带无关的论文提交，是已知阻塞。

**只传了 `fair_benchmark` 里的静态表，没传 `score.py`**：红线 2 在 HPC 上物理不可违反（实测 `find src -name score.py` = 0）。

两个冻结输入在 HPC 上的散列与冻结记录逐字相同：
`track0_statics.csv` = `085e8b5e…`、`531_basin_list.txt` = `cd2d3d46…`。

## 二、环境：五次尝试全败，根因已定

| 尝试 | 结果 |
|---|---|
| conda create（默认） | 插件报错，未创建 |
| conda create + `CONDA_NO_PLUGINS=true` | `CondaValueError`：libmamba 求解器不被识别 |
| venv + pip 装契约版本 | pandas 2.3.3 无兼容轮子 → 退回源码编译 → numpy 构建依赖失败 |
| conda + `--solver=classic -c conda-forge` | conda 本体 "unexpected error" 崩溃 |

**根因两条**：① CentOS 7 的 glibc 2.17 太老，契约钉死的 `pandas==2.3.3` 没有可用预编译轮子；
② 这台机器的 conda 23.10.0 自身求解器/插件配置是坏的，三种绕法都崩。

按项目停止规则（同一问题失败 5 次必须停下问人），**停止尝试，交用户决定**。

候选契约钉死 `numpy==1.26.4 / pandas==2.3.3 / pyarrow==22.0.0`，
而 `runtime/dependencies.py` 会**真的核实际安装版本**，因此候选运行在 HPC 上必然被拒。

**候选运行是唯一受阻的一步**：建数据底座、逐流域核查、极端流域判定都不经过依赖闸门。

## 三、数据底座已在 HPC 重建并核查通过

`sbatch` 到 `hcpu48`（作业 201854，COMPLETED，ExitCode 0:0，**19 秒**），登录节点未跑计算。

| 检查项 | HPC 结果 |
|---|---|
| 流域数 | 64 |
| 封存区间命中行 | **0** |
| 产物文件散列钉死 | 17 |
| 核查总判定 | **all passed: True** |
| 极端流域判定 | **53 标准 / 11 不稳定** |
| 11 个 unstable 流域 | 与 Windows 侧**逐个相同** |

## 四、关键发现：内容跨平台一致，字节不一致

用平台无关的**内容摘要**（排序后逐行规范化数值再散列）对账：

| 项 | Windows | Linux(HPC) | 相符 |
|---|---|---|---|
| `targets.parquet` 内容摘要 | `9f3e9361…d48d192` | `9f3e9361…d48d192` | ✅ |
| `features.parquet` 内容摘要 | `9e0ebb10…3fbd0c01` | `9e0ebb10…3fbd0c01` | ✅ |
| 判定记录内容摘要（去掉内嵌包散列） | `51c1f290…a830fd4` | `51c1f290…a830fd4` | ✅ |
| 行数 | 210 432 | 210 432 | ✅ |

但**字节散列全都不同**：

| 文件 | Windows | Linux |
|---|---|---|
| `features.parquet` | `1c13a083…` | `c2288dd3…` |
| `targets.parquet` | `3d070cd4…` | `d539f07c…` |
| `static_attributes.json` | `a59be77c…` | `0e0993a8…` |

两个原因，都已查实：

1. **parquet**：pyarrow 版本不同（22.0.0 vs 20.0.0），容器元数据不同。
2. **JSON**：**换行符**。实测 Windows 侧该文件 **1861 个 CRLF、0 个 LF**，Linux 侧 **0 个 CRLF、1861 个 LF**。
   根因是 `real_source.py` / `packages.py` 用 `Path.write_text(...)` 写 JSON 而**未传 `newline="\n"`**，
   Python 文本模式在 Windows 上把 `\n` 译成 `\r\n`。

### 这意味着什么

**本项目大量证据建立在 sha256 钉死的产物之上，而这些散列是平台相关的**，因此
**不能拿它们当跨平台复现的证据**。内容层面是可复现的（上表内容摘要逐个相同），字节层面不是。

此前"两次运行逐字节一致"的结论仍然成立——那是**同机**两次。跨平台是另一回事，本次首次测到。

**换行符这一条是可修的真缺陷**（加 `newline="\n"`），但修了会改变 Windows 侧重建产物的散列，
与已冻结在证据文档里的数字对不上。Linux 上本来就正确，故**未擅自修改**，交用户决定。

## 五、当前状态与待决

- ✅ HPC 工作区、代码、数据底座、核查、极端流域判定 —— 全部完成且通过。
- ⛔ **候选运行受阻**，等一个决定：把契约版本改成 `nh_final` 实际装的三个
  （numpy 2.3.3 / pandas 2.3.2 / pyarrow 20.0.0），作为**另一组硬编码的冻结版本集**
  （仍硬编码，不从环境读取——否则闸门退化成恒等式，正是复核 P5 批评的问题）。
  代价：HPC 上的候选结果是**独立一次运行，不是本地那次的复现**。
- ⛔ 换行符缺陷是否修（会改动 Windows 侧散列）。
- 未做：并行执行接线、531 底座、软链接测试。
