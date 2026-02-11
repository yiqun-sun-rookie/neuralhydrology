# -*- coding: utf-8 -*-
import argparse
import pandas as pd
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--csv', default='data/haihe/hydrobasins/lev12/haihe_hydrobasins_lev12_list.csv')
    args = ap.parse_args()

    p = Path(args.csv)
    df = pd.read_csv(p)
    col = 'SUB_AREA'
    if col not in df.columns:
        raise SystemExit('SUB_AREA not found')

    s = df[col].dropna().astype(float)
    q = s.quantile([0.05, 0.25, 0.5, 0.75, 0.95])

    bins = [0, 50, 100, 200, 500, 1000, 1e9]
    labels = ['<50', '50-100', '100-200', '200-500', '500-1000', '>1000']
    b = pd.cut(s, bins=bins, labels=labels, include_lowest=True)
    cnt = b.value_counts().reindex(labels).fillna(0).astype(int)

    print('path', p)
    print('count', s.size)
    print('min', round(s.min(), 2))
    print('max', round(s.max(), 2))
    print('mean', round(s.mean(), 2))
    print('median', round(s.median(), 2))
    print('q05', round(q.loc[0.05], 2))
    print('q25', round(q.loc[0.25], 2))
    print('q75', round(q.loc[0.75], 2))
    print('q95', round(q.loc[0.95], 2))
    print('bins')
    for k in labels:
        print(k, int(cnt.loc[k]))


if __name__ == '__main__':
    main()
