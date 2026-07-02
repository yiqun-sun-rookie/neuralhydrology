"""L2 analysis: what does the untargeted attack do HYDROLOGICALLY (not just to NSE)?

Two signatures, from the recorded adversarial hydrographs (l1l2_records/*.npz):
  (A) Flood-peak corruption: relative change in the predicted peak MAGNITUDE and the
      shift in predicted peak TIMING (adversarial vs clean model, around each obs peak).
  (B) Mass-balance violation: per WATER-YEAR runoff coefficient RC = sum(Q)/sum(P_clean).
      RC>1 over a full water year = streamflow exceeding precipitation = water from nothing
      (storage release is water-year-neutral, so this is a genuine conservation breach).
      Reported as the ATTACK-INDUCED rate: frac(RC_adv>1) minus frac(RC_clean>1), and
      broken down by snow regime. Uses clean precip as the real available-water denominator.

    python src/adversarial/scripts/analyze_l2_signatures.py
"""
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.signal import find_peaks

REPO = Path(__file__).resolve().parents[3]
RES = REPO / "results" / "05_adversarial_robustness" / "id18_s100"
REC = RES / "l1l2_records"
DATA_DIR = REPO / "data" / "camels_us"
from neuralhydrology.datasetzoo.camelsus import load_camels_us_attributes

W = 7               # +/- window (days) to locate the predicted peak around each obs peak
MIN_WY_DAYS = 300   # require a near-complete water year for a mass-balance ratio


def water_year(dates):
    d = pd.to_datetime(dates)
    return (d.year + (d.month >= 10).astype(int)).to_numpy()


rows = []
for f in sorted(REC.glob("*.npz")):
    z = np.load(f, allow_pickle=True)
    q_obs, q_clean, q_adv, p = z["q_obs"], z["q_clean"], z["q_adv"], z["p_clean"]
    mask, dates = z["mask"].astype(bool), z["dates"]
    basin = f.stem
    if dates.size == 0 or dates.size != q_adv.size:
        continue

    # (A) flood-peak magnitude + timing on the predicted hydrographs
    obs = q_obs.astype(float).copy()
    obs[~mask] = -np.inf
    finite = obs[np.isfinite(obs)]
    mag_changes, timing_shifts = [], []
    if finite.size:
        thr = np.quantile(finite, 0.95)
        peaks, _ = find_peaks(np.nan_to_num(obs, neginf=-1e30), height=thr, distance=14)
        for d in peaks:
            lo, hi = max(0, d - W), min(len(q_adv), d + W + 1)
            cwin, awin = q_clean[lo:hi], q_adv[lo:hi]
            cmag = cwin.max()
            if cmag <= 0.1:
                continue
            mag_changes.append(float((awin.max() - cmag) / cmag))
            timing_shifts.append(float(awin.argmax() - cwin.argmax()))

    # (B) water-year runoff-coefficient violation (RC = sumQ / sumP_clean)
    wy = water_year(dates)
    rc_adv, rc_clean = [], []
    for y in np.unique(wy):
        sel = wy == y
        if sel.sum() < MIN_WY_DAYS:
            continue
        sp = p[sel].sum()
        if sp <= 0:
            continue
        rc_adv.append(q_adv[sel].sum() / sp)
        rc_clean.append(q_clean[sel].sum() / sp)
    rc_adv, rc_clean = np.array(rc_adv), np.array(rc_clean)

    rows.append(dict(
        basin=basin, n_peaks=len(mag_changes),
        peak_mag_rel=float(np.median(mag_changes)) if mag_changes else np.nan,
        peak_timing_abs=float(np.median(np.abs(timing_shifts))) if timing_shifts else np.nan,
        n_wy=len(rc_adv),
        viol_adv=float((rc_adv > 1).mean()) if len(rc_adv) else np.nan,
        viol_clean=float((rc_clean > 1).mean()) if len(rc_clean) else np.nan,
        rc_adv_med=float(np.median(rc_adv)) if len(rc_adv) else np.nan,
        rc_clean_med=float(np.median(rc_clean)) if len(rc_clean) else np.nan,
    ))

df = pd.DataFrame(rows)
attrs = load_camels_us_attributes(DATA_DIR, basins=df["basin"].tolist())
attrs.index = attrs.index.astype(str).str.zfill(8)
df["basin"] = df["basin"].astype(str).str.zfill(8)
df = df.merge(attrs[["frac_snow", "runoff_ratio"]], left_on="basin", right_index=True, how="left")
snow = df["frac_snow"] > 0.2

print(f"basins: {len(df)} | snow(n={int(snow.sum())}) rain(n={int((~snow).sum())})")

print("\n--- (A) flood-peak corruption (predicted adv vs clean, around obs peaks) ---")
print(f"median predicted-peak magnitude change : {df.peak_mag_rel.median():+.3f}  "
      f"(snow {df.loc[snow,'peak_mag_rel'].median():+.3f} | rain {df.loc[~snow,'peak_mag_rel'].median():+.3f})")
print(f"median |predicted-peak timing shift|   : {df.peak_timing_abs.median():.2f} d  "
      f"(snow {df.loc[snow,'peak_timing_abs'].median():.2f} | rain {df.loc[~snow,'peak_timing_abs'].median():.2f})")

print("\n--- (B) mass-balance violation: water-year runoff coefficient RC>1 ---")
pooled_adv = df["viol_adv"].mean(); pooled_clean = df["viol_clean"].mean()
print(f"basin-mean frac of water-years with RC>1 : adv {pooled_adv:.3f} vs clean {pooled_clean:.3f}  "
      f"(attack-induced +{pooled_adv - pooled_clean:.3f})")
print(f"  snow: adv {df.loc[snow,'viol_adv'].mean():.3f} vs clean {df.loc[snow,'viol_clean'].mean():.3f}  "
      f"(+{(df.loc[snow,'viol_adv']-df.loc[snow,'viol_clean']).mean():.3f})")
print(f"  rain: adv {df.loc[~snow,'viol_adv'].mean():.3f} vs clean {df.loc[~snow,'viol_clean'].mean():.3f}  "
      f"(+{(df.loc[~snow,'viol_adv']-df.loc[~snow,'viol_clean']).mean():.3f})")
pushed = df[(df.viol_clean < 0.001) & (df.viol_adv > 0.001)]
print(f"basins with NO clean RC>1 water-year but >=1 under attack: {len(pushed)}/{len(df)}")
print(f"median RC (adv vs clean): {df.rc_adv_med.median():.3f} vs {df.rc_clean_med.median():.3f}")

df.to_csv(RES / "l2_signatures_summary.csv", index=False)
print(f"\nsaved -> {RES / 'l2_signatures_summary.csv'}")
