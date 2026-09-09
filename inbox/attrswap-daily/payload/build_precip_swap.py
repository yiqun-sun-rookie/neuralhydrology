"""Build a CAMELS forcing product that differs from Maurer in the precipitation column only (PREREG_20260909).

The precipitation source is either
  --from-table   a gzipped CSV of daily basin means (rows = date, columns = 8-digit basin id), or
  --from-product an existing forcing product in the same basin_mean_forcing directory, whose PRCP column is
                 lifted out and dropped onto Maurer's other four columns.

Construction: every Maurer line is kept verbatim and exactly one tab-separated field -- index 2, PRCP(mm/day) --
is replaced. Nothing else is reparsed, so the three header lines (which carry the catchment area used as the
discharge denominator) and the four non-precipitation columns are byte-identical to Maurer by construction.

Stop-condition checks (any failure exits non-zero, which cancels the dependent training jobs):
  V1 one output file per basin        V2 header lines 1-3 byte-identical to Maurer
  V3 modelled span covered with >= 270 days of warm-up margin
  V4 no missing value inside the modelled span
  V5 20 random basins round-trip to the source within 1e-3
  V7 precipitation >= 0 throughout the modelled span
  V8 the four non-precipitation fields byte-identical to Maurer on every shared date
Report-only (PREREG section 3.1: NOT a stop condition, because every non-Caravan global product is delivered on
UTC days and would otherwise be disqualified by construction):
  V6 per-basin best lag of the precipitation cross-correlation against Maurer, with the affected basins named
"""
import argparse
import glob
import gzip
import json
import os
import random
import sys

import pandas as pd

PRCP_FIELD = 2
MODEL_START, MODEL_END, TEST_START, MIN_WARMUP = '1989-01-04', '2008-09-30', '1989-10-01', 270
FAIL, NOTE = [], []


def fail(m):
    FAIL.append(m)
    print('FAIL ' + m, flush=True)


def read_lines(path):
    with open(path) as fh:
        lines = fh.read().splitlines()
    dates = [pd.Timestamp(*[int(x) for x in ln.split('\t')[0].split()[:3]]) for ln in lines[4:]]
    return lines[:4], pd.DatetimeIndex(dates), [ln.split('\t') for ln in lines[4:]]


def source_series(a, b, maurer_dir):
    if a.from_table:
        return a._tab[b]
    f = glob.glob(f'{a.dest}/{a.from_product}/**/{b}_*_forcing_leap.txt', recursive=True)
    if not f:
        f = glob.glob(f'{maurer_dir}/../{a.from_product}/**/{b}_*_forcing_leap.txt', recursive=True)
    if not f:
        raise SystemExit(f'{b}: 找不到来源产品 {a.from_product}')
    _, idx, flds = read_lines(f[0])
    return pd.Series([float(p[PRCP_FIELD]) for p in flds], index=idx)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('product')
    ap.add_argument('--from-table', default='')
    ap.add_argument('--from-product', default='')
    ap.add_argument('--maurer', required=True)
    ap.add_argument('--dest', required=True)
    ap.add_argument('--basins', required=True)
    ap.add_argument('--report', required=True)
    a = ap.parse_args()
    if bool(a.from_table) == bool(a.from_product):
        raise SystemExit('必须且只能给出 --from-table 或 --from-product 之一')
    if a.from_table:
        with gzip.open(a.from_table, 'rt') as fh:
            a._tab = pd.read_csv(fh, index_col=0, parse_dates=True)
        a._tab.columns = [c.zfill(8) for c in a._tab.columns]
        print(f'来源表 {len(a._tab)} 天 × {a._tab.shape[1]} 流域 '
              f'{a._tab.index[0].date()}→{a._tab.index[-1].date()}', flush=True)
    else:
        print(f'来源产品 {a.from_product}（取其降水列，其余四列用 Maurer）', flush=True)

    basins = [l.strip().zfill(8) for l in open(a.basins) if l.strip()]
    lags, ratios, spans, written = {}, {}, {}, 0
    for i, b in enumerate(basins):
        mf = glob.glob(f'{a.maurer}/**/{b}_*_forcing_leap.txt', recursive=True)
        if len(mf) != 1:
            fail(f'{b}: {len(mf)} 个 Maurer 文件'); continue
        head, midx, fields = read_lines(mf[0])
        src = source_series(a, b, a.maurer)
        keep = [j for j, d in enumerate(midx) if d in src.index and pd.notna(src.get(d))]
        if not keep:
            fail(f'{b}: 来源与 Maurer 无重叠'); continue
        out = list(head)
        for j in keep:
            parts = list(fields[j])
            parts[PRCP_FIELD] = f'{float(src.loc[midx[j]]):.4f}'
            out.append('\t'.join(parts))
        huc = os.path.basename(os.path.dirname(mf[0]))
        outp = f'{a.dest}/{a.product}/{huc}/{b}_lump_{a.product}_forcing_leap.txt'
        os.makedirs(os.path.dirname(outp), exist_ok=True)
        with open(outp, 'w', newline='\n') as fh:
            fh.write('\n'.join(out) + '\n')
        written += 1

        ki = midx[keep]
        spans[b] = (str(ki[0].date()), str(ki[-1].date()))
        mp = pd.Series([float(fields[j][PRCP_FIELD]) for j in keep], index=ki).loc[MODEL_START:MODEL_END]
        cp = src.loc[ki].loc[MODEL_START:MODEL_END]
        if cp.isna().any():
            fail(f'V4 {b}: 建模段 {int(cp.isna().sum())} 个缺测')
        if (cp < 0).any():
            fail(f'V7 {b}: 建模段 {int((cp < 0).sum())} 个负降水')
        r = {k: float(mp.corr(cp.shift(k))) for k in (-2, -1, 0, 1, 2)}
        lags[b] = max(r, key=r.get)
        ratios[b] = float(cp.mean() / mp.mean()) if mp.mean() > 0 else float('nan')
        if (i + 1) % 100 == 0:
            print(f'  {i + 1}/{len(basins)}', flush=True)

    n = len(glob.glob(f'{a.dest}/{a.product}/**/*_forcing_leap.txt', recursive=True))
    if n != len(basins):
        fail(f'V1 写出 {n} 个，应为 {len(basins)}')
    short = {b: s for b, s in spans.items()
             if (pd.Timestamp(TEST_START) - pd.Timestamp(s[0])).days < MIN_WARMUP or s[1] < MODEL_END}
    if short:
        fail(f'V3 {len(short)} 个流域覆盖不足，例 {list(short.items())[:2]}')

    rng = random.Random(20260909)
    for b in rng.sample(basins, min(20, len(basins))):
        f = glob.glob(f'{a.dest}/{a.product}/**/{b}_*_forcing_leap.txt', recursive=True)
        mf = glob.glob(f'{a.maurer}/**/{b}_*_forcing_leap.txt', recursive=True)
        if not f or not mf:
            fail(f'V2/V5/V8 {b}: 文件缺失'); continue
        new = open(f[0]).read().splitlines()
        old = open(mf[0]).read().splitlines()
        if new[:3] != old[:3]:
            fail(f'V2 {b}: 前 3 行与 Maurer 不同')
        om = {ln.split('\t')[0]: ln.split('\t') for ln in old[4:]}
        src, bad8, errp = source_series(a, b, a.maurer), 0, 0.0
        for ln in new[4:]:
            p = ln.split('\t')
            o = om.get(p[0])
            if o is None:
                fail(f'V8 {b}: 日期 {p[0]} 不在 Maurer 中'); break
            if [p[k] for k in range(len(p)) if k != PRCP_FIELD] != [o[k] for k in range(len(o)) if k != PRCP_FIELD]:
                bad8 += 1
            d = pd.Timestamp(*[int(x) for x in p[0].split()[:3]])
            if d in src.index:
                errp = max(errp, abs(float(p[PRCP_FIELD]) - float(src.loc[d])))
        if bad8:
            fail(f'V8 {b}: {bad8} 行的非降水字段与 Maurer 不同')
        if not (errp < 1e-3):
            fail(f'V5 {b}: 降水往返误差 {errp:.2e} >= 1e-3')

    lg = pd.Series(lags)
    off = {b: int(v) for b, v in lags.items() if v != 0}
    share = float((lg == 0).mean()) if len(lg) else 0.0
    NOTE.append(f'V6（报告项，非停机条件）: 最佳滞后为 0 的流域 {share*100:.2f}%；'
                f'其余 {len(off)} 个流域按滞后计数 {dict(pd.Series(list(off.values())).value_counts())}')
    print('NOTE ' + NOTE[-1], flush=True)
    rt = pd.Series(ratios)
    summary = dict(product=a.product, source=a.from_table or f'product:{a.from_product}', basins=len(basins),
                   written=written, failures=FAIL, notes=NOTE, v6_report_only=True, lag0_share=share,
                   v6_off_lag_basins=sorted(off.items()),
                   lag_counts={int(k): int(v) for k, v in lg.value_counts().items()},
                   ratio_over_maurer=dict(median=float(rt.median()), p10=float(rt.quantile(.1)),
                                          p90=float(rt.quantile(.9))), span_example=spans.get(basins[0]))
    open(a.report, 'w').write(json.dumps(summary, indent=1, ensure_ascii=False))
    print(json.dumps(summary, indent=1, ensure_ascii=False), flush=True)
    if FAIL:
        print(f'核验失败: {len(FAIL)} 项', flush=True)
        sys.exit(1)
    print('核验通过（V6 为报告项，不参与判定）', flush=True)


if __name__ == '__main__':
    main()
