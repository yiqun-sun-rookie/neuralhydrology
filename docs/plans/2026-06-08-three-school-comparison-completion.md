# 三学派概念模型对比 完全补全计划 (Idea 10, CAMELS-US 531)

- **创建**: 2026-06-08
- **背景**: 第三轮独立审核 (goal-driven) 确认 GR4J/XAJ/HBV repro_v01 对比整体公平、结论稳健，
  但存在若干**可关闭的公平性/复现性缺口** + **不可关闭的 inherent caveat**。本计划把可关闭项在
  **单一统一协议**下全部关闭，并把 inherent 项显式披露。
- **审核状态**: 本计划已经 **3 轮独立审核** (见文末审核轨迹)，实质修订 4 处。
- **关联**: memory `gr4j_playbook_531.md` 第三轮审核段 / `docs/technical/gr4j_playbook_iteration_log.md`
  第三轮审核段 / spec `docs/superpowers/specs/2026-06-07-gr4j-pdd-playbook-design.md`。

---

## Goal

在**单一统一协议**下关闭 XAJ/HBV/GR4J 对比的全部**可关闭**公平性/复现性缺口，并诚实披露
irreducible caveat。

**Scope 边界 (反 over-claim, 审核 F11)**: 本计划只承诺 **"协议公平 (same calibration/validation
protocol) + 残余诚实披露"**，**不承诺** "模型对等" 或 "绝对公平"。三个是结构不同的模型，能拉平的是
流程，拉不平的是模型本身与 PET 偏好。

---

## 统一协议锁定 (审核 F8)

| 维度 | 锁定值 |
|---|---|
| split | cal 1999-10-01..2008-09-30 / eval 1989-10-01..1999-09-30 (repro_v01) |
| forcing | maurer |
| PET | priestley_taylor (CAMELS 标准 Addor 2017) |
| warmup | warmup_year=True (Kratzert) |
| bounds | 各模型 literature-tight (GR4J v1 / HBV v1 / XAJ v1) |
| init | init_mean=0.5, init_sigma=0.3 |
| **budget** | **5000×3 (统一锁定)** |
| metric | compute_metrics NSE, eval 期 |

**三家状态矩阵 (审核 F3/F8)**:

| 模型 | 当前 | 需动作 |
|---|---|---|
| **GR4J** | `gr4j_pdd_cma_FINAL_pt_v1` = PT/warmup/v1/5k×3/metadata 全字段 | ✅ **已就绪, 零动作 (参考基准)** |
| **HBV** | v7_PT_tight_warmup 0.6170 数据有效但 metadata 补丁拼装 | 需干净 warmup 5k×3 重跑 (S1) |
| **XAJ** | `xaj_pdd_cma_PT_v1_warmup` 0.6232 仅 2000×2 | 需收敛确认 (S3a) → 全 531 5k×3 (S3b, 镀金) |

---

## Stages

> Status 标记: `[ ]` 未开始 / `[~]` 进行中 / `[x]` 完成。必要性: **must** = 最小完整路径 /
> **gold** = 顶刊镀金 / **cond** = 条件触发。

### `[ ]` S0 — 冻结统一协议 spec (must)
- **Goal**: 把上方协议 + 状态矩阵 + must/gold 分层 + 叫停点写成不可漂移的基准。
- **Success Criteria**: 本文档即 spec; 后续任何 run 的 metadata 必须匹配协议 5 字段。
- **Tests**: 人工核对每个产出 run 的 metadata vs 协议表。

### `[ ]` S2 — HBV runner 加 `--bounds-preset` CLI (must, **先于 S1**, 审核 F1)
- **Goal**: 关闭 E 根因——HBV bounds 当前仅 env `HBV_BOUNDS` 控制 (默认 v5-宽)。加真正的
  `--bounds-preset {v1,v5}` CLI, threading 到 `calibrate_hbv_lite_cma` → `simulate_hbv_lite` 的
  `PARAM_BOUNDS` 选择, 不再依赖 import-time env。
- **Success Criteria**: `--bounds-preset v1` 与 `HBV_BOUNDS=v1` 旧路径结果 **bit-exact**。
- **Tests**: 2-basin 对拍, param/nse L1 = 0。
- **Risk**: HBV bounds 在 `hbv_lite_numpy` 模块 import 时定; 改成运行时传参需小心不破坏 Numba
  cache。改完跑 sanity_check + 2-basin bit-exact 自检。

### `[ ]` S1 — HBV-PT-v1-warmup 全 531 干净重跑 (must, 审核 F1/F4)
- **Goal**: 关闭 A 的 provenance + 行使 C 的新 metadata 字段。用 S2 的 `--bounds-preset v1`
  跑干净的全 531 warmup, 输出新 subdir。
- **命令**:
  ```
  python -X utf8 -m src.scl_hydro.scripts.run_hbv_lite_cma_repro_v01 \
    --pet-method priestley_taylor --warmup-year --bounds-preset v1 \
    --trials 5000 --restarts 3 --workers 10 \
    --output-subdir hbv_lite_cma_FINAL_pt_v1_warmup   # (需 S2 支持 output-subdir/bounds-preset)
  ```
- **Success Criteria**: median≈**0.6170**; 逐 basin params 与旧 v7_PT_tight max\|Δ\|=0 (同标定);
  metadata 含 pet/warmup/init/bounds/budget 五字段。
- **Tests**: param 对拍旧 v7 (L1=0); metadata 字段校验; `--skip-existing` 可断点续。
- **Note**: 旧 v7_PT_tight / v7_PT_tight_warmup **归档不删** (S8)。

### `[ ]` S3a — XAJ-PT-v1-warmup 子集 40 跑 5k×3 (must, 审核 F7/F9)
- **Goal**: 关闭 B——确认 XAJ 在 headline 配置下 2k×2 已收敛。
- **命令**:
  ```
  python -X utf8 -m src.xaj_global_pilot.scripts.run_xaj_pdd_cma_repro_v01 \
    --pet-method priestley_taylor --warmup-year --bounds-preset v1 \
    --trials 5000 --restarts 3 --workers 10 \
    --manifest src/xaj_global_pilot/configs/xaj_playbook_iter_subset_40.txt \
    --output-subdir xaj_pdd_cma_PT_v1_warmup_5k3_sub40
  ```
- **Success Criteria (可证伪)**: 同 40-basin 上 \|median(5k×3) − median(2k×2)\| **≤ 0.005** → 收敛,
  B 关闭, headline XAJ 仍可报 2k×2 + 脚注。
- **Tests**: 取现有 2k×2 全 531 在这 40 basin 的 median 对比。
- **成本**: ~1.2h。

### `[ ]` S3-branch — 若 S3a 不收敛 (cond, 审核 F2)
- **触发**: \|5k−2k\| > 0.005。
- **动作**: 跑 S3b 全 531 5k×3 → **重算整张对比表 (Δ/胜率/gap/参数效率论点) + 重新独立审核**。
  XAJ headline 改为 5k×3 数字。**不可只换数字不重审。**

### `[ ]` S3b — XAJ 全 531 5k×3 (gold, 审核 F9)
- **Goal**: 顶刊镀金——三家完全同预算 (全 5k×3)。
- **命令**: 同 S3a 去掉 `--manifest` (默认 531), `--output-subdir xaj_pdd_cma_FINAL_pt_v1_5k3`,
  `--skip-existing` 可续。
- **Success Criteria**: median 稳定; bit-exact 自检。
- **Tests**: `verify_xaj_rerun --subdir xaj_pdd_cma_FINAL_pt_v1_5k3 --n 2` → L1=0。
- **成本**: ~16h (可断点续)。

### `[ ]` S4 — 文献基线 SAC-SMA/FUSE/mHM 独立重算 (gold, 审核 F6)
- **Goal**: 去掉"文献数字依赖前 session 声明"。
- **Success Criteria**: 在确切 531 / 公共子集 (n=479/492) 上重算, 与文献吻合。
- **Fallback (审核 F6)**: 若 published per-basin 数据本地不可得 → **标注外部来源 + 不阻塞主线**,
  绝不让 S4 卡住其他 Stage。
- **Tests**: 重算 n 与文献 median 对比。

### `[ ]` S6 — 重生成统一表 + 独立 agent 复审 (must, 审核 F12)
- **Goal**: 用全 5k×3 (或 S3a 收敛后的 headline) 重生成最终对比表。
- **Success Criteria**: **派独立 agent (新 context) 复审**重生成的结果与表, 出 PASS 报告。
  自审不算 (审核 F12)。
- **Tests**: 独立 agent 报告 + 三 headline median 从 CSV 重算一致。

### `[ ]` S7 — caveat 披露段 (must, 审核 F11)
- **Goal**: 把 3 条 irreducible 写进论文/文档。
- **Success Criteria**: ① PET 双行表 (PT + Oudin 都列); ② 参数效率非因果 (GR4J 结构功劳, 不反推
  "参数越少越好"); ③ arid gap +0.127 (5k×3 反更差); ④ XAJ 0.2% 渗漏文档化 (caveat⑦)。

### `[ ]` S8 — 治理: 归档 + commit (must, 审核 F10)
- **Goal**: handbook 硬规则——旧文件归档不删, 改动入库。
- **Success Criteria**: 被替换的旧结果 (HBV non-warmup 引用 / XAJ 2k×2 headline) 归档说明; 文档
  (memory/log/spec/本计划) + 代码 (HBV runner) 改动 commit; `git status` 干净。

---

## S5 — XAJ 渗漏修复 (剔除主线, 审核 F5)

**默认不做**: 仅文档化为 caveat⑦ (0.2% 对 NSE 无实质影响)。
**若坚持修码**: 必须独立分支隔离 + 明示"改 XAJ forward 会破坏现有 XAJ 结果 bit-exact → 触发全 531
重跑 + 全部重审"。高风险低收益, 不进最小/镀金路径。

---

## 执行路径 (审核 F9)

- **最小完整 (≈2h, 够 WRR)**: S0 → S2 → S1 → S3a → S6 → S7 → S8。
- **顶刊镀金 (+~17h)**: 再加 S3b + S4。
- **叫停点**: S3a 收敛 (≤0.005) 即可停在最小完整; 是否冲 S3b 全 531 由成本-收益决定。

## Irreducible 残余 (做完也存在, 只披露不消除)

1. **PET 口径**: GR4J vs XAJ 部分 Δ 来自 PT 选择 (XAJ 偏好 Oudin)。→ S7 PET 双行披露。
2. **参数效率非因果**: GR4J 8 参赢是其结构在 CAMELS 高效 (文献已知), 非 playbook 功劳。→ S7 归因。
3. **arid 短板**: gap +0.127, 加预算反更差。→ S7 caveat。

---

## 3 轮独立审核轨迹 (计划自审)

- **审核 1 (顺序/缺失)**: F1 S2 须先于 S1 (否则 E 假关闭); F2 缺 XAJ 不收敛分支; F3 GR4J 未标零动作;
  F4 缺每跑 bit-exact + skip-existing。
- **审核 2 (可证伪/风险)**: F5 S5 改码破坏 bit-exact → 降级文档化; F6 S4 缺数据 fallback;
  F7 判据要量化阈值; F8 "统一预算" 未定义 → 锁 5k×3 + 状态矩阵。
- **审核 3 (范围/治理/over-claim)**: F9 缺 must/gold 分层叫停点; F10 缺归档+commit 治理;
  F11 不得宣称绝对公平 → 加 Scope 边界; F12 S6 复审须独立 agent。

**残余风险 (审核也消不掉)**: 本计划只能保证"协议公平 + 诚实披露"; 模型本身不对等、PET 偏好差异、
参数效率归因属解释层面, 非计划可关闭。
