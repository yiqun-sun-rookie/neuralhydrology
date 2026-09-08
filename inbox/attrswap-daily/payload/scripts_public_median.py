"""Print '<public-422 median NSE> <n>' for one run dir (argv[1])."""
import sys, pandas as pd
rd = sys.argv[1]
d = pd.read_csv(rd + '/test/model_epoch030/test_metrics.csv', dtype={'basin': str})
d['basin'] = d['basin'].str.zfill(8)
hold = set(l.strip() for l in open('basin_lists/holdout_107.txt') if l.strip())
pub = d[~d['basin'].isin(hold)]
print(f"{pub['NSE'].median():.6f} {len(pub)}")
