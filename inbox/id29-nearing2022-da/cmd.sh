#!/bin/bash
# seq=435 只读: 按训练留出率拆解我们与作者的差, 检验 2026-08-25 登记的判别性预测
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
source ~/miniconda3/etc/profile.d/conda.sh && conda activate nh_final 2>/dev/null
cd "$ROOT"
echo "=== HEADER ==="
head -1 closure_20260810/aggregation/evaluations/time_split_vs_author.csv || true
echo "=== PREDICTION TEST ==="
python - <<'PY' 2>&1 || echo "analysis unavailable"
import pandas as pd
p='closure_20260810/aggregation/evaluations/time_split_vs_author.csv'
d=pd.read_csv(p)
print("rows:", len(d), "| cols:", list(d.columns))
cand=[c for c in d.columns if 'train' in c.lower()]
print("train-holdout col candidates:", cand)
# 只看自回归、预见期 1
sub=d.copy()
for c in ('family','eval_id'):
    if c in sub.columns:
        sub=sub[sub[c].astype(str).str.contains('AR|autoregression', case=False, na=False)]
        break
if 'lead' in sub.columns: sub=sub[sub['lead']==1]
print("AR lead-1 rows:", len(sub))
dc=[c for c in sub.columns if 'diff' in c.lower()]
print("difference cols:", dc)
tr=cand[0] if cand else None
te=[c for c in sub.columns if 'test' in c.lower() and 'hold' in c.lower()]
te=te[0] if te else None
mc=[c for c in sub.columns if c.lower() in ('metric','metric_name')]
mc=mc[0] if mc else None
print("using:", tr, te, mc, dc[:1])
if tr and te and mc and dc:
    dcol=dc[0]
    for metric in ('NSE','Alpha-NSE'):
        m=sub[sub[mc]==metric]
        if len(m)==0: continue
        print(f"\n### {metric}: 我们-作者 的差 (行=训练留出, 列=测试留出)")
        print(m.pivot_table(index=tr, columns=te, values=dcol, aggfunc='mean').round(4).to_string())
    print("\n### 各训练留出率下 超差项数 / 总项数")
    wc=[c for c in sub.columns if 'within' in c.lower()]
    if wc:
        g=sub.groupby(tr)[wc[0]].agg(['size', lambda s: int((~s.astype(bool)).sum())])
        g.columns=['总项数','超差项数']
        print(g.to_string())
PY
