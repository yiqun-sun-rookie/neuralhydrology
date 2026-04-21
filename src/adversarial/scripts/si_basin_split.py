"""SI Basin-Split Analysis: verify whether adversarial vulnerability differs
across the model's original training / validation / test catchment splits.

Usage:
    python src/adversarial/scripts/si_basin_split.py

Outputs statistics for the Supporting Information document.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

# ---------------------------------------------------------------------------
# Paths (relative to project root)
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[3]

MERGED_JSON = PROJECT_ROOT / "results" / "adversarial_eval" / "full" / "merged_all.json"

# The 674-basin split files used to train the victim CudaLSTM model
SPLIT_DIR = PROJECT_ROOT / "examples" / "01-Introduction" / "splits"
TRAIN_FILE = SPLIT_DIR / "full_674_basins_train_basins.txt"
VAL_FILE = SPLIT_DIR / "full_674_basins_val_basins.txt"
TEST_FILE = SPLIT_DIR / "full_674_basins_test_basins.txt"

# The 540-basin list used as input to the adversarial experiment
ADV_BASIN_FILE = PROJECT_ROOT / "src" / "adversarial" / "data" / "train_540_basins.txt"


def load_basin_list(path: Path) -> list[str]:
    """Load a text file with one basin ID per line."""
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def fmt_iqr(values: np.ndarray) -> str:
    """Format median [Q25, Q75]."""
    med = np.nanmedian(values)
    q25 = np.nanpercentile(values, 25)
    q75 = np.nanpercentile(values, 75)
    return f"{med:+.3f} [{q25:+.3f}, {q75:+.3f}]"


def print_separator(title: str) -> None:
    print()
    print("=" * 72)
    print(f"  {title}")
    print("=" * 72)


def main() -> None:
    # ------------------------------------------------------------------
    # 1. Load data
    # ------------------------------------------------------------------
    print_separator("LOADING DATA")

    with open(MERGED_JSON) as f:
        records = json.load(f)
    df = pd.DataFrame(records)
    print(f"Loaded {len(df)} records from {MERGED_JSON.name}")
    print(f"Unique basins in results: {df['basin'].nunique()}")
    print(f"Attacks: {sorted(df['attack'].unique())}")
    print(f"Epsilons: {sorted(df['epsilon'].unique())}")

    # Load split files
    train_basins = set(load_basin_list(TRAIN_FILE))
    val_basins = set(load_basin_list(VAL_FILE))
    test_basins = set(load_basin_list(TEST_FILE))
    all_674 = train_basins | val_basins | test_basins

    print(f"\nModel split sizes: train={len(train_basins)}, "
          f"val={len(val_basins)}, test={len(test_basins)}, "
          f"total={len(all_674)}")

    # Load adversarial basin list
    adv_basins = set(load_basin_list(ADV_BASIN_FILE))
    print(f"Adversarial experiment basin list: {len(adv_basins)}")

    # ------------------------------------------------------------------
    # 2. Cross-reference: which splits do adversarial basins belong to?
    # ------------------------------------------------------------------
    print_separator("BASIN PROVENANCE CHECK")

    result_basins = set(df["basin"].unique())
    in_train = result_basins & train_basins
    in_val = result_basins & val_basins
    in_test = result_basins & test_basins
    in_none = result_basins - all_674

    print(f"Basins in results that belong to:")
    print(f"  Train split:  {len(in_train)}")
    print(f"  Val split:    {len(in_val)}")
    print(f"  Test split:   {len(in_test)}")
    print(f"  No split:     {len(in_none)}")

    # Check adversarial input list overlap with splits
    adv_in_train = adv_basins & train_basins
    adv_in_val = adv_basins & val_basins
    adv_in_test = adv_basins & test_basins
    print(f"\nAdversarial basin list ({len(adv_basins)}) overlap with model splits:")
    print(f"  Train: {len(adv_in_train)}, Val: {len(adv_in_val)}, Test: {len(adv_in_test)}")

    # Check which basins from the 540 list are missing from results
    adv_missing = adv_basins - result_basins
    print(f"\nBasins in adversarial list but missing from results: {len(adv_missing)}")
    if adv_missing:
        print(f"  IDs: {sorted(adv_missing)}")

    # ------------------------------------------------------------------
    # 3. Assign split labels to each record
    # ------------------------------------------------------------------
    def assign_split(basin_id: str) -> str:
        if basin_id in train_basins:
            return "train"
        elif basin_id in val_basins:
            return "val"
        elif basin_id in test_basins:
            return "test"
        return "unknown"

    df["split"] = df["basin"].apply(assign_split)

    # ------------------------------------------------------------------
    # 4. CORE ANALYSIS: Auto-PGD, eps=0.1, lp, untargeted
    # ------------------------------------------------------------------
    print_separator("CORE ANALYSIS: Auto-PGD, eps=0.1, constraint=lp, target=untargeted")

    mask = (
        (df["attack"] == "auto_pgd")
        & (df["epsilon"] == 0.1)
        & (df["constraint"] == "lp")
        & (df["target"] == "untargeted")
    )
    core = df.loc[mask].copy()
    print(f"Records matching filter: {len(core)}")
    print(f"Unique basins: {core['basin'].nunique()}")
    print(f"Split distribution: {dict(core.groupby('split')['basin'].nunique())}")

    # Per-basin aggregation (mean across samples)
    basin_agg = core.groupby(["basin", "split"]).agg(
        delta_nse_mean=("delta_nse", "mean"),
        nse_clean_mean=("nse_clean", "mean"),
        kge_clean_mean=("kge_clean", "mean"),
        n_samples=("delta_nse", "count"),
    ).reset_index()

    print(f"\nPer-basin aggregated: {len(basin_agg)} basins")

    # ------------------------------------------------------------------
    # 5. Per-split statistics table
    # ------------------------------------------------------------------
    print_separator("PER-SPLIT STATISTICS (per-basin mean delta-NSE)")

    headers = [
        "Split", "N basins", "N records",
        "Median delta-NSE", "Mean delta-NSE", "IQR",
        "Frac(delta-NSE < -1)", "Median clean-NSE", "Median clean-KGE"
    ]
    print(f"{'Split':<8} {'N_bas':>6} {'N_rec':>6} "
          f"{'Med dNSE':>12} {'Mean dNSE':>12} {'Q25':>8} {'Q75':>8} "
          f"{'frac<-1':>8} {'Med cNSE':>10} {'Med cKGE':>10}")
    print("-" * 100)

    split_data = {}  # for Kruskal-Wallis test
    for split_name in ["train", "val", "test"]:
        sub = basin_agg[basin_agg["split"] == split_name]
        if len(sub) == 0:
            print(f"{split_name:<8} {'0':>6} {'0':>6}  (no data)")
            continue

        vals = sub["delta_nse_mean"].values
        split_data[split_name] = vals
        n_basins = len(sub)
        n_records = int(sub["n_samples"].sum())
        med = np.nanmedian(vals)
        mean = np.nanmean(vals)
        q25 = np.nanpercentile(vals, 25)
        q75 = np.nanpercentile(vals, 75)
        frac_below = np.mean(vals < -1)
        med_clean_nse = np.nanmedian(sub["nse_clean_mean"].values)
        med_clean_kge = np.nanmedian(sub["kge_clean_mean"].values)

        print(f"{split_name:<8} {n_basins:>6d} {n_records:>6d} "
              f"{med:>+12.4f} {mean:>+12.4f} {q25:>+8.4f} {q75:>+8.4f} "
              f"{frac_below:>8.3f} {med_clean_nse:>10.4f} {med_clean_kge:>10.4f}")

    # Overall
    all_vals = basin_agg["delta_nse_mean"].values
    print("-" * 100)
    print(f"{'ALL':<8} {len(basin_agg):>6d} {int(basin_agg['n_samples'].sum()):>6d} "
          f"{np.nanmedian(all_vals):>+12.4f} {np.nanmean(all_vals):>+12.4f} "
          f"{np.nanpercentile(all_vals, 25):>+8.4f} {np.nanpercentile(all_vals, 75):>+8.4f} "
          f"{np.mean(all_vals < -1):>8.3f} "
          f"{np.nanmedian(basin_agg['nse_clean_mean'].values):>10.4f} "
          f"{np.nanmedian(basin_agg['kge_clean_mean'].values):>10.4f}")

    # ------------------------------------------------------------------
    # 6. Statistical tests across splits
    # ------------------------------------------------------------------
    print_separator("STATISTICAL TESTS ACROSS SPLITS")

    groups = [v for v in split_data.values() if len(v) > 0]
    group_names = [k for k, v in split_data.items() if len(v) > 0]

    if len(groups) >= 2:
        # Kruskal-Wallis test
        h_stat, p_kw = stats.kruskal(*groups)
        print(f"Kruskal-Wallis H test ({' vs '.join(group_names)}):")
        print(f"  H = {h_stat:.4f}, p = {p_kw:.4e}")
        print(f"  Interpretation: {'No significant difference' if p_kw > 0.05 else 'Significant difference'} "
              f"at alpha=0.05")

        # Pairwise Mann-Whitney U tests
        if len(groups) >= 2:
            print("\nPairwise Mann-Whitney U tests:")
            for i in range(len(groups)):
                for j in range(i + 1, len(groups)):
                    u_stat, p_mw = stats.mannwhitneyu(groups[i], groups[j], alternative="two-sided")
                    eff_size = u_stat / (len(groups[i]) * len(groups[j]))  # rank-biserial
                    print(f"  {group_names[i]} vs {group_names[j]}: "
                          f"U={u_stat:.0f}, p={p_mw:.4e}, "
                          f"rank-biserial r={2 * eff_size - 1:.4f}")
    else:
        print(f"Only {len(groups)} split(s) have data — cannot run between-group tests.")
        print("NOTE: All adversarial-tested basins belong to the TRAINING split.")

    # ------------------------------------------------------------------
    # 7. Extended analysis: all epsilons for Auto-PGD
    # ------------------------------------------------------------------
    print_separator("EXTENDED: Auto-PGD across ALL epsilons (lp, untargeted)")

    mask_apgd = (
        (df["attack"] == "auto_pgd")
        & (df["constraint"] == "lp")
        & (df["target"] == "untargeted")
    )
    apgd = df.loc[mask_apgd]

    print(f"{'Epsilon':>8} {'N_bas':>6} {'N_rec':>6} "
          f"{'Med dNSE':>12} {'Mean dNSE':>12} {'Q25':>8} {'Q75':>8} "
          f"{'frac<-1':>8}")
    print("-" * 72)

    for eps in sorted(apgd["epsilon"].unique()):
        sub = apgd[apgd["epsilon"] == eps]
        # Per-basin mean
        basin_vals = sub.groupby("basin")["delta_nse"].mean().values
        n_basins = len(basin_vals)
        n_records = len(sub)
        med = np.nanmedian(basin_vals)
        mean_val = np.nanmean(basin_vals)
        q25 = np.nanpercentile(basin_vals, 25)
        q75 = np.nanpercentile(basin_vals, 75)
        frac_below = np.mean(basin_vals < -1)
        print(f"{eps:>8.2f} {n_basins:>6d} {n_records:>6d} "
              f"{med:>+12.4f} {mean_val:>+12.4f} {q25:>+8.4f} {q75:>+8.4f} "
              f"{frac_below:>8.3f}")

    # ------------------------------------------------------------------
    # 8. Analysis for ALL attack types at eps=0.1
    # ------------------------------------------------------------------
    print_separator("ALL ATTACKS at eps=0.1 (lp, untargeted)")

    mask_e01 = (
        (df["epsilon"] == 0.1)
        & (df["constraint"] == "lp")
        & (df["target"] == "untargeted")
    )
    e01 = df.loc[mask_e01]

    print(f"{'Attack':<25} {'N_bas':>6} {'N_rec':>6} "
          f"{'Med dNSE':>12} {'Mean dNSE':>12} {'IQR':>20} "
          f"{'frac<-1':>8}")
    print("-" * 100)

    for atk in sorted(e01["attack"].unique()):
        sub = e01[e01["attack"] == atk]
        basin_vals = sub.groupby("basin")["delta_nse"].mean().values
        n_basins = len(basin_vals)
        n_records = len(sub)
        med = np.nanmedian(basin_vals)
        mean_val = np.nanmean(basin_vals)
        q25 = np.nanpercentile(basin_vals, 25)
        q75 = np.nanpercentile(basin_vals, 75)
        frac_below = np.mean(basin_vals < -1)
        print(f"{atk:<25} {n_basins:>6d} {n_records:>6d} "
              f"{med:>+12.4f} {mean_val:>+12.4f} [{q25:>+.3f}, {q75:>+.3f}] "
              f"{frac_below:>8.3f}")

    # ------------------------------------------------------------------
    # 9. Clean model performance by split
    # ------------------------------------------------------------------
    print_separator("CLEAN MODEL PERFORMANCE BY SPLIT (from adversarial records)")

    # Use all records to get clean NSE/KGE per basin (should be same across attacks)
    clean_per_basin = df.groupby(["basin", "split"]).agg(
        nse_clean=("nse_clean", "first"),
        kge_clean=("kge_clean", "first"),
    ).reset_index()

    print(f"{'Split':<8} {'N':>6} {'Med NSE':>10} {'Mean NSE':>10} "
          f"{'Med KGE':>10} {'Mean KGE':>10} "
          f"{'NSE>0.5':>8} {'NSE>0.7':>8}")
    print("-" * 80)

    for split_name in ["train", "val", "test", "ALL"]:
        if split_name == "ALL":
            sub = clean_per_basin
        else:
            sub = clean_per_basin[clean_per_basin["split"] == split_name]
        if len(sub) == 0:
            print(f"{split_name:<8} {'0':>6}  (no data)")
            continue

        nse_vals = sub["nse_clean"].values
        kge_vals = sub["kge_clean"].values
        print(f"{split_name:<8} {len(sub):>6d} "
              f"{np.nanmedian(nse_vals):>10.4f} {np.nanmean(nse_vals):>10.4f} "
              f"{np.nanmedian(kge_vals):>10.4f} {np.nanmean(kge_vals):>10.4f} "
              f"{np.mean(nse_vals > 0.5):>8.3f} {np.mean(nse_vals > 0.7):>8.3f}")

    # ------------------------------------------------------------------
    # 10. Summary for SI document
    # ------------------------------------------------------------------
    print_separator("SUMMARY FOR SI DOCUMENT")

    print("Key finding: The adversarial experiment used 540 basins from the")
    print(f"examples/01-Introduction/splits/full_674_basins_train_basins.txt file.")
    print(f"These basins correspond ENTIRELY to the model's training split.")
    print(f"  - Basins in results from train split: {len(in_train)}")
    print(f"  - Basins in results from val split:   {len(in_val)}")
    print(f"  - Basins in results from test split:  {len(in_test)}")
    print()

    if len(in_val) == 0 and len(in_test) == 0:
        print("IMPORTANT: The claim that 'adversarial vulnerability does not differ")
        print("systematically across the original training, validation, and test")
        print("catchment splits' CANNOT be verified from the current data, because")
        print("all adversarial-tested basins belong to the training split.")
        print()
        print("The adversarial basin list (train_540_basins.txt) is identical to")
        print("full_674_basins_train_basins.txt. No val/test basins were attacked.")
        print()
        print("To support this claim, the adversarial experiment would need to be")
        print("extended to include the 67 validation and 67 test basins.")
    else:
        print("The data contains basins from multiple splits — split comparison is valid.")

    print()
    print("Overall Auto-PGD eps=0.1 statistics (all basins, all from train split):")
    if len(core) > 0:
        basin_dnse = core.groupby("basin")["delta_nse"].mean()
        print(f"  N basins:        {len(basin_dnse)}")
        print(f"  Median delta-NSE: {basin_dnse.median():+.4f}")
        print(f"  Mean delta-NSE:   {basin_dnse.mean():+.4f}")
        print(f"  IQR:              [{basin_dnse.quantile(0.25):+.4f}, {basin_dnse.quantile(0.75):+.4f}]")
        print(f"  Frac < -1:        {(basin_dnse < -1).mean():.3f}")
        print(f"  Min:              {basin_dnse.min():+.4f}")
        print(f"  Max:              {basin_dnse.max():+.4f}")


if __name__ == "__main__":
    main()
