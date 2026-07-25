# ID25 Coarse→Fine Hierarchy Value Test (PUB) — Design

Date: 2026-07-25
Status: design, awaiting user review
Owner: ID25 Global Flood Hierarchy (non-strategic side line)

## 0. Why this exists

The coarse layer (region water-balance state, GRACE/soil supervised) is validated but
its two cheap zero-download improvement levers both failed: per-region loss weighting is
inert (v2: arid 0.344→0.341) and capacity is marginal (v3: arid 0.341→0.403, below the
0.45 line and at the seed-noise floor). The arid third is confirmed ceiling-limited by a
~35% human-water linear trend the meteorological forcing cannot see.

Per the project north-star, the coarse layer must earn value **in the hierarchy** —
ungauged / data-sparse forecasting — not by grinding GRACE NSE. This test is the
go/no-go: does the frozen coarse regional state `s_region` help a fine-layer basin
streamflow model in **prediction in ungauged basins (PUB)**, beyond what the same raw
regional inputs already provide?

## 1. Goal & decision criterion

Feed `s_region` into a fine-layer CAMELS-US LSTM and measure streamflow skill on
spatially held-out (ungauged) basins, against two controls.

- **Arm 1 (hierarchy):** basin-local forcing + `s_region` = the coarse model's 2-D output
  (`grace_reg`, `soil_reg`), monthly, forward-filled to daily.
- **Arm 2 (fair control):** basin-local forcing + the coarse model's raw inputs at tile
  resolution (6 forcing aggregates + 4 tile statics = 10 features). Same regional
  information the coarse layer saw, but no learned coarse state.
- **Arm 3 (baseline):** basin-local forcing only (no regional information).

**Hierarchy earns its keep iff Arm 1 > Arm 2 AND Arm 1 > Arm 3**, on held-out-basin
median NSE, by a margin beyond noise (paired per-basin, see §5).

Note the deliberately self-unfavourable asymmetry: Arm 1 carries **2** features, Arm 2
carries **10**. If the learned 2-D state beats 10 raw regional features, that is a strong
positive; if it does not, the learned state adds no compressed value over raw inputs.

## 2. Architecture — reuse, do not rebuild

- Fine layer = a stock neuralhydrology `cudalstm` run. Template: the existing 531 baseline
  `src/adversarial/baseline_531/configs/camels_us/full_training/reproduce_531_nse074.yml`
  (cudalstm, hidden 128, seq 365, epochs 30, NSE loss, 5 Daymet dynamic inputs, 14 CAMELS
  static attributes). All arms share these hyperparameters; arms differ only in the extra
  dynamic inputs.
- `s_region` and the tile-raw features are injected through neuralhydrology's native
  `additional_features` mechanism (a pickle of `{basin_id: DataFrame}` merged into the
  forcing). **No change to the neuralhydrology package source.**

## 3. Data flow

1. `build_region_state_features.py` — for every basin in the test set (§4), look up its
   tile in `region_membership.csv`, and build a daily DataFrame spanning 1980–2014 with 12
   columns:
   - `grace_reg`, `soil_reg` — coarse model output for that tile (from
     `coarse_v3_pred.npz`, `pred[:, :, {grace,soil}]`), monthly → daily forward-fill.
   - `tile_prcp, tile_srad, tile_swe, tile_tmax, tile_tmin, tile_vp` — tile monthly forcing
     aggregates (from `region_forcing.nc`), monthly → daily forward-fill.
   - `tile_st_precip, tile_st_tmax, tile_st_swe, tile_st_srad` — the 4 coarse static
     attributes (constant per tile).
   Save one pickle `{basin: df}`. All three arms read the **same** pickle and select
   different columns via `dynamic_inputs`, so the arms are guaranteed identical except for
   the selected regional features. Basin ids zero-padded to 8-char CAMELS gauge ids.
2. `make_pub_fold.py` — restrict to basins in both `531_basin_list.txt` and the membership
   map. Map basins → tiles. **Stratify tiles by aridity band** (arid/mid/wet, the coarse
   annual-precip terciles) and hold out ~25% of tiles per band (fixed seed), so the
   held-out set is aridity-representative. Write `pub_train_basins.txt` (basins in kept
   tiles) and `pub_test_basins.txt` (basins in held-out tiles). No test basin shares a tile
   with any train basin (strict PUB).
3. Three configs `arm1_hier.yml`, `arm2_rawtile.yml`, `arm3_baseline.yml`, all derived from
   the template, all pointing at the same `additional_features` pickle, differing only in
   the appended `dynamic_inputs`.
4. Train each arm; evaluate on `pub_test_basins.txt`; compare (§5).

## 4. PUB protocol

- **Spatial split:** tile-based, single fold first (user-chosen scope). ~25% of tiles held
  out, stratified by aridity band, fixed seed. Basins = 531-list ∩ membership.
- **Temporal periods:**
  - Train (kept tiles' basins): 01/10/1999 – 30/09/2008.
  - Validation (early-stop, a slice of kept tiles' basins): 01/10/2008 – 30/09/2011.
  - Test (held-out tiles' basins): **01/10/1989 – 30/09/1999**.
  The test period lies entirely **before** the GRACE label window (2002+), so `s_region`
  on the test basins/period is computed with **zero remote-sensing labels** — a clean
  demonstration of the north-star property "computable where no remote sensing exists".
- `s_region` comes from the **frozen** coarse model (GRU is causal → no future leakage).

## 5. Metrics & stopping

- Per held-out basin NSE for each arm; report **median** and the arid/mid/wet breakdown.
- Primary comparison is **paired per-basin**: distribution of (Arm1 − Arm2) and
  (Arm1 − Arm3) NSE across held-out basins; report median paired difference and a sign /
  bootstrap test over basins. The many held-out basins give statistical power at a single
  seed; add seeds only if the paired result is borderline.
- **Go:** Arm1 − Arm2 median paired diff clearly > 0 (and Arm1 > Arm3) → expand to full
  k-fold (the "full 4-fold" scope) to confirm across all regions before any write-up.
- **No-go:** Arm1 ≈ Arm2 → the learned coarse state adds nothing over raw regional inputs;
  stop cheaply and record the negative result. This is a legitimate north-star answer.

## 6. Validity / leakage analysis

- Test period pre-GRACE → `s_region` label-free on the test set.
- Tile-based holdout → no train basin shares a tile with a test basin; the coarse model
  never saw streamflow anyway (GRACE-supervised only).
- Both Arm 1 and Arm 2 receive tile-level information equally, so any residual tile-level
  memorization cancels in the Arm1−Arm2 delta, which is the decision quantity.
- Frozen causal coarse model → no temporal leakage into either training or test.

## 7. Known risks (surface, do not hide)

- `s_region` is a **monthly** slow signal; at daily streamflow resolution it may be too
  coarse to help → possible genuine null. A null is a real finding, not a failure.
- In arid held-out tiles the coarse state is weak (ceiling ~0.4–0.5); report per-band so a
  humid-only benefit is not hidden behind an aggregate median.
- Compute: 3 full LSTM runs (~400 train basins × 30 epochs) on the local RTX 4070Ti; GPU
  use requires user consent at run time.

## 8. Reuse & artifacts

- Reuse: `reproduce_531_nse074.yml` template, `531_basin_list.txt`, `region_membership.csv`,
  `coarse_v3_pred.npz`, `region_forcing.nc`.
- New code (all under `src/25_global_flood_hierarchy/fine/`): `build_region_state_features.py`,
  `make_pub_fold.py`, three arm configs, `evaluate_arms.py`.
- Freeze-before-run discipline: commit new code before each training run; big binaries stay
  gitignored.
