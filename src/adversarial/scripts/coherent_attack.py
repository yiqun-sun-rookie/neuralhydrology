"""Coherent single-delta adversarial attack driver (Plan v4, F2+F3+F9).

Core idea: one shared per-basin perturbation delta_cal[T_cal, F] (one value per
calendar day x feature, T_cal = N_windows + seq_length - 1). The windowed model
input is delta_cal.unfold(0, T, 1) (a differentiable sliding-window view), so
gradients flow back to the shared delta automatically and the threat model is a
realizable single forcing-series tamper (NOT a per-window oracle).

- Metric: last-step (predict_last_n=1) test-period NSE, concatenated over all
  N windows -> matches the official RegressionTester per-basin NSE.
- Chunked per-chunk backward keeps memory bounded and is exact (NSE affine in
  ss_res; ss_tot is an obs-only constant).
- F9: temperature channels (Tmin idx1, Tmax idx2) are tied for EVERY attack
  (gradient avg or copy-one-sample) because Maurer Tmax==Tmin.

Attacks: fgsm, apgd, random_sign (best-of-K), gaussian (best-of-K). linf only.
"""
from __future__ import annotations

import torch

TEMP_IDX = (1, 2)  # Tmin(C), Tmax(C) in ID18 dynamic_inputs order


def _tie_grad(g: torch.Tensor) -> torch.Tensor:
    """F9 for GRADIENT attacks: the shared temperature DOF has gradient g_Tmin+g_Tmax,
    so set both temp-channel grads to that sum -> sign() is shared and equals sign(g1+g2)."""
    a, b = TEMP_IDX
    s = g[..., a] + g[..., b]
    g = g.clone()
    g[..., a] = s
    g[..., b] = s
    return g


def _tie_copy(delta: torch.Tensor) -> torch.Tensor:
    """F9 for RANDOM attacks: sample ONE temperature perturbation and copy it to both
    channels (channel a -> b), instead of averaging two independent draws."""
    a, b = TEMP_IDX
    delta = delta.clone()
    delta[..., b] = delta[..., a]
    return delta


def _clamp(delta: torch.Tensor, eps: float) -> torch.Tensor:
    return delta.clamp(-eps, eps)


class CoherentBasin:
    """Holds one basin's clean windows + precomputed NSE denominator for coherent attacks."""

    def __init__(self, wrapper, x_d, x_s, y_obs, device, chunk: int = 512):
        self.w = wrapper
        self.X = x_d                       # [N, T, F] normalized clean windows
        self.x_s = x_s                     # [N, n_static]
        self.N, self.T, self.F = x_d.shape
        self.T_cal = self.N + self.T - 1
        self.chunk = chunk
        self.device = device
        y_last = y_obs[:, -1, 0]           # [N]
        self.mask = ~torch.isnan(y_last)
        self.y_last = y_last
        yt = y_last[self.mask]
        self.ss_tot = ((yt - yt.mean()) ** 2).sum().clamp(min=1e-10)
        self.zero = torch.zeros(self.T_cal, self.F, device=device)
        self.nse_clean = self.nse(self.zero)
        # continuous clean forcing series for physical/statistical constraints (F2 §3:
        # constraints act on delta_cal[1,T_cal,F] -> statistical preserves WHOLE-test-period moments)
        self.clean_cal = torch.cat([x_d[0], x_d[1:, -1, :]], dim=0)  # [T_cal, F]
        self.feat = list(wrapper.dynamic_features)
        _sc = wrapper.get_scaler()
        _c, _s = _sc.get("xarray_feature_center"), _sc.get("xarray_feature_scale")
        self.center = torch.tensor([float(_c[f].values) for f in self.feat], device=device)
        self.scale = torch.tensor([float(_s[f].values) for f in self.feat], device=device)
        # QObs scaler for physical-space KGE (F5: KGE beta non-invariant -> must denormalize)
        tv = wrapper.cfg.target_variables[0] if hasattr(wrapper.cfg, "target_variables") else "QObs(mm/d)"
        self.q_center = float(_c[tv].values)
        self.q_scale = float(_s[tv].values)

    # --- forward / metric (no grad) ---
    def _preds(self, delta_cal: torch.Tensor) -> torch.Tensor:
        preds = []
        with torch.no_grad():
            for i in range(0, self.N, self.chunk):
                j1 = min(i + self.chunk, self.N)
                d_slice = delta_cal[i:j1 + self.T - 1]                 # [c+T-1, F]
                dw = d_slice.unfold(0, self.T, 1).permute(0, 2, 1)     # [c, T, F]
                xa = self.X[i:j1] + dw
                yh = self.w.forward(xa, self.x_s[i:j1])
                preds.append(yh[:, -1, 0])
        return torch.cat(preds)

    def nse(self, delta_cal: torch.Tensor) -> float:
        p = self._preds(delta_cal)
        m = self.mask
        return float(1.0 - ((self.y_last[m] - p[m]) ** 2).sum() / self.ss_tot)

    # --- gradient of ss_res/ss_tot w.r.t. delta_cal (chunked per-chunk backward) ---
    def grad(self, delta_cal: torch.Tensor) -> torch.Tensor:
        delta = delta_cal.detach().clone().requires_grad_(True)
        for i in range(0, self.N, self.chunk):
            j1 = min(i + self.chunk, self.N)
            d_slice = delta[i:j1 + self.T - 1]
            dw = d_slice.unfold(0, self.T, 1).permute(0, 2, 1)
            xa = self.X[i:j1] + dw
            yh = self.w.forward(xa, self.x_s[i:j1])        # cuDNN auto-disabled (needs grad)
            pl = yh[:, -1, 0]
            m = self.mask[i:j1]
            ss_res = ((self.y_last[i:j1][m] - pl[m]) ** 2).sum()
            (ss_res / self.ss_tot).backward()              # accumulate into delta.grad
        return delta.grad.detach()

    # --- attacks (maximize ss_res/ss_tot == minimize NSE) ---
    def fgsm(self, eps: float) -> float:
        g = _tie_grad(self.grad(self.zero))
        delta = _clamp(eps * g.sign(), eps)            # temp channels equal (g tied)
        return self.nse_clean - self.nse(delta)

    def apgd(self, eps: float, n_iter: int = 50) -> float:
        init = torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps)
        delta = _clamp(_tie_copy(init), eps)           # init tied (copy one temp sample)
        best_nse = self.nse(delta)
        alpha = 2 * eps
        for t in range(n_iter):
            g = _tie_grad(self.grad(delta))
            delta = _clamp(delta + alpha * g.sign(), eps)  # stays tied (delta tied + tied step)
            cur = self.nse(delta)
            if cur < best_nse:
                best_nse = cur
            if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
                alpha *= 0.5
        return self.nse_clean - best_nse

    def apgd_record(self, eps: float, n_iter: int = 50, seed: int = 0) -> dict:
        """Untargeted APGD (identical attack to apgd) that RECORDS the best perturbation
        and the denormalized daily hydrographs, for L1 (per-forcing-variable / temporal
        attribution of the perturbation) and L2 (hydrological-signature + water-balance)
        analysis. The attack itself is unchanged; only extra tensors are returned."""
        import numpy as np
        g0 = torch.Generator(device=self.device).manual_seed(seed)
        delta = _clamp(_tie_copy(torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)), eps)
        best_nse, best_delta = self.nse(delta), delta
        alpha = 2 * eps
        for t in range(n_iter):
            g = _tie_grad(self.grad(delta))
            delta = _clamp(delta + alpha * g.sign(), eps)
            cur = self.nse(delta)
            if cur < best_nse:
                best_nse, best_delta = cur, delta
            if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
                alpha *= 0.5
        # denormalized daily series (physical units) at the last day of each window
        q_obs = self.y_last * self.q_scale + self.q_center                       # [N] mm/d
        q_clean = self._preds(self.zero) * self.q_scale + self.q_center          # [N] mm/d
        q_adv = self._preds(best_delta) * self.q_scale + self.q_center           # [N] mm/d
        p_idx = torch.arange(self.T - 1, self.T_cal, device=self.device)         # last-day cal idx per window
        p_clean = self.clean_cal[p_idx, 0] * self.scale[0] + self.center[0]      # [N] mm/d (clean precip)
        # L1 channel attribution: leave-one-out damage drop on the ACHIEVED attack.
        # Energy per channel is uninformative here (L-inf saturates every channel to +/-eps);
        # attrib[c] = how much adversarial damage is lost when channel c cannot be perturbed.
        _groups = {"precip": [0], "temp": list(TEMP_IDX), "srad": [3], "vp": [4]}
        attrib = {}
        for _name, _chs in _groups.items():
            d2 = best_delta.clone()
            d2[:, _chs] = 0.0
            attrib[_name] = float(self.nse(d2) - best_nse)                       # >= 0, damage lost
        return dict(
            D_nse=self.nse_clean - best_nse, nse_adv=best_nse, nse_clean=self.nse_clean,
            attrib=attrib,
            delta=best_delta.detach().cpu().numpy().astype(np.float32),          # [T_cal, F] standardized
            q_obs=q_obs.detach().cpu().numpy().astype(np.float32),
            q_clean=q_clean.detach().cpu().numpy().astype(np.float32),
            q_adv=q_adv.detach().cpu().numpy().astype(np.float32),
            p_clean=p_clean.detach().cpu().numpy().astype(np.float32),
            mask=self.mask.detach().cpu().numpy(),
            feat=list(self.feat),
        )

    def random_sign(self, eps: float, k: int, gen: torch.Generator) -> float:
        best_nse = self.nse_clean
        for _ in range(k):
            v = torch.randint(0, 2, (self.T_cal, self.F), generator=gen, device=self.device) * 2 - 1
            delta = _clamp(_tie_copy(eps * v.float()), eps)   # copy one temp sample (F9)
            cur = self.nse(delta)
            if cur < best_nse:
                best_nse = cur
        return self.nse_clean - best_nse

    def gaussian(self, eps: float, k: int, gen: torch.Generator) -> float:
        best_nse = self.nse_clean
        for _ in range(k):
            v = torch.randn(self.T_cal, self.F, generator=gen, device=self.device) * eps
            delta = _clamp(_tie_copy(v), eps)                 # copy one temp sample (F9)
            cur = self.nse(delta)
            if cur < best_nse:
                best_nse = cur
        return self.nse_clean - best_nse

    # --- Yang reconciliation (Exp6): physical-space KGE on the untargeted-APGD adversary ---
    def _kge_phys(self, preds: torch.Tensor) -> float:
        """KGE in physical mm/d (F5: denormalize; beta=mean-ratio is NOT affine-invariant)."""
        m = self.mask
        yt = self.y_last[m] * self.q_scale + self.q_center
        yp = preds[m] * self.q_scale + self.q_center
        vt, vp = yt - yt.mean(), yp - yp.mean()
        r = (vt * vp).sum() / (vt.norm() * vp.norm() + 1e-10)
        alpha = yp.std() / (yt.std() + 1e-10)
        beta = yp.mean() / (yt.mean() + 1e-10)
        return float(1 - torch.sqrt((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2))

    def apgd_kge(self, eps: float, n_iter: int = 50, seed: int = 0) -> dict:
        g0 = torch.Generator(device=self.device).manual_seed(seed)
        delta = _clamp(_tie_copy(torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)), eps)
        best_nse, best_delta = self.nse(delta), delta
        alpha = 2 * eps
        for t in range(n_iter):
            g = _tie_grad(self.grad(delta))
            delta = _clamp(delta + alpha * g.sign(), eps)
            cur = self.nse(delta)
            if cur < best_nse:
                best_nse, best_delta = cur, delta
            if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
                alpha *= 0.5
        kge_c = self._kge_phys(self._preds(self.zero))
        kge_a = self._kge_phys(self._preds(best_delta))
        return dict(D_nse=self.nse_clean - best_nse, nse_adv=best_nse,
                    kge_clean=kge_c, kge_adv=kge_a, dkge=kge_a - kge_c)

    # --- targeted attacks (Exp3): concentrate the attack on high/low-flow days ---
    def _flow_mask(self, kind: str) -> torch.Tensor:
        """Last-step day mask for 'flood' (obs > p90) / 'lowflow' (obs < p10) / 'untargeted' (all valid)."""
        yl, m = self.y_last, self.mask
        if kind == "untargeted":
            return m
        valid = yl[m]
        thr = torch.quantile(valid, 0.9 if kind == "flood" else 0.1)
        return m & (yl > thr if kind == "flood" else yl < thr)

    def _grad_masked(self, delta_cal: torch.Tensor, tmask: torch.Tensor) -> torch.Tensor:
        """Gradient of (masked ss_res / ss_tot) — concentrates the attack on the target days."""
        delta = delta_cal.detach().clone().requires_grad_(True)
        for i in range(0, self.N, self.chunk):
            j1 = min(i + self.chunk, self.N)
            d_slice = delta[i:j1 + self.T - 1]
            dw = d_slice.unfold(0, self.T, 1).permute(0, 2, 1)
            yh = self.w.forward(self.X[i:j1] + dw, self.x_s[i:j1])
            tm = tmask[i:j1]
            if tm.any():
                ss = ((self.y_last[i:j1][tm] - yh[:, -1, 0][tm]) ** 2).sum()
                (ss / self.ss_tot).backward()
        return delta.grad.detach() if delta.grad is not None else torch.zeros_like(delta)

    def apgd_targeted(self, eps: float, target: str, n_iter: int = 50, seed: int = 0,
                      return_kge: bool = False):
        """APGD optimizing damage on the target-day subset; reports OVERALL damage D=nse_clean-nse_adv.
        If return_kge, also reports physical-space ΔKGE on the same adversary (KGE over all valid
        days, like Exp6) as dict(D_nse, kge_clean, kge_adv, dkge)."""
        tmask = self._flow_mask(target)
        g0 = torch.Generator(device=self.device).manual_seed(seed)
        delta = _clamp(_tie_copy(torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)), eps)
        best, best_delta = self.nse(delta), delta
        alpha = 2 * eps
        for t in range(n_iter):
            g = _tie_grad(self._grad_masked(delta, tmask))
            delta = _clamp(delta + alpha * g.sign(), eps)
            cur = self.nse(delta)            # OVERALL nse (untargeted metric), so flood vs lowflow is comparable
            if cur < best:
                best, best_delta = cur, delta
            if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
                alpha *= 0.5
        d_nse = self.nse_clean - best
        if not return_kge:
            return d_nse
        kge_c = self._kge_phys(self._preds(self.zero))
        kge_a = self._kge_phys(self._preds(best_delta))
        return dict(D_nse=d_nse, kge_clean=kge_c, kge_adv=kge_a, dkge=kge_a - kge_c)

    # --- constraint-ablation (Exp2): lp / physical / statistical on the full series ---
    def _constraint(self, level: str, eps: float):
        from src.adversarial.constraints import LpConstraint, PhysicalConstraint, StatisticalConstraint
        if level == "lp":
            return LpConstraint(epsilon=eps, norm="linf")
        cls = PhysicalConstraint if level == "physical" else StatisticalConstraint
        return cls(epsilon=eps, feature_names=self.feat,
                   scaler_center=self.center, scaler_scale=self.scale)

    def _proj_c(self, delta: torch.Tensor, con) -> torch.Tensor:
        """Project delta_cal through a constraint applied on the full [1,T_cal,F] series, then tie temp."""
        x_adv = (self.clean_cal + delta).unsqueeze(0)
        x_proj = con.project(self.clean_cal.unsqueeze(0), x_adv)
        return _tie_copy(x_proj[0] - self.clean_cal)

    def apgd_c(self, eps: float, level: str, n_iter: int = 50, seed: int = 0) -> float:
        con = self._constraint(level, eps)
        g0 = torch.Generator(device=self.device).manual_seed(seed)
        init = torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)
        delta = self._proj_c(_tie_copy(init), con)
        best = self.nse(delta)
        alpha = 2 * eps
        for t in range(n_iter):
            g = _tie_grad(self.grad(delta))
            delta = self._proj_c(delta + alpha * g.sign(), con)
            cur = self.nse(delta)
            if cur < best:
                best = cur
            if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
                alpha *= 0.5
        return self.nse_clean - best

    # --- detectability (KS): untargeted APGD adversary, per-feature KS 2-sample p ---
    def apgd_detect(self, eps: float, n_iter: int = 50, seed: int = 0) -> dict:
        """Untargeted APGD at eps; returns ΔNSE and a per-feature KS 2-sample p-value between
        the clean and perturbed WHOLE-period marginal of each forcing feature (detectability)."""
        from scipy.stats import ks_2samp
        g0 = torch.Generator(device=self.device).manual_seed(seed)
        delta = _clamp(_tie_copy(torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)), eps)
        best, best_delta = self.nse(delta), delta
        alpha = 2 * eps
        for t in range(n_iter):
            g = _tie_grad(self.grad(delta))
            delta = _clamp(delta + alpha * g.sign(), eps)
            cur = self.nse(delta)
            if cur < best:
                best, best_delta = cur, delta
            if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
                alpha *= 0.5
        clean = self.clean_cal.detach().cpu().numpy()
        adv = (self.clean_cal + best_delta).detach().cpu().numpy()
        ks_p = [float(ks_2samp(clean[:, f], adv[:, f]).pvalue) for f in range(self.F)]
        return dict(D_nse=self.nse_clean - best, nse_adv=best, ks_p=ks_p, ks_p_min=min(ks_p))

    # --- causal-trigger (Exp4): perturb only pre-event days, damage the flood-peak prediction ---
    def _find_peaks(self, p_quantile: float = 0.95, distance: int = 14) -> list:
        """Flood-peak window indices p (0..N-1) on the valid last-step obs series."""
        import numpy as np
        from scipy.signal import find_peaks
        y = self.y_last.detach().cpu().numpy().copy().astype(float)
        y[~self.mask.cpu().numpy()] = -np.inf
        finite = y[np.isfinite(y)]
        if finite.size == 0:
            return []
        thr = float(np.quantile(finite, p_quantile))
        peaks, _ = find_peaks(np.nan_to_num(y, neginf=-1e30), height=thr, distance=distance)
        return peaks.tolist()

    def _pre_event_mask(self, peaks: list, pre_window: int) -> torch.Tensor:
        """[T_cal, F] bool: True on the pre_window calendar days before each peak day."""
        m = torch.zeros(self.T_cal, self.F, dtype=torch.bool, device=self.device)
        for p in peaks:
            cp = p + self.T - 1                       # peak calendar day
            lo = max(0, cp - pre_window)
            m[lo:cp, :] = True
        return m

    def _peak_nse(self, preds: torch.Tensor, peaks: torch.Tensor) -> float:
        yt = self.y_last[peaks]
        yp = preds[peaks]
        sst = ((yt - yt.mean()) ** 2).sum().clamp(min=1e-10)
        return float(1.0 - ((yt - yp) ** 2).sum() / sst)

    def apgd_causal(self, eps: float, pre_window: int, n_iter: int = 50, seed: int = 0) -> dict:
        """APGD with delta restricted to pre-event calendar days, optimizing the peak windows'
        squared error. best starts from the clean (zero) adversary so reported damage is >= 0
        (the attacker can always do nothing). Reports peak-only and overall last-step ΔNSE."""
        peaks_list = [p for p in self._find_peaks() if self.mask[p]]
        if not peaks_list:
            return dict(D_peak=float("nan"), D_overall=float("nan"), n_peaks=0)
        peaks = torch.tensor(peaks_list, device=self.device)
        pmask = self._pre_event_mask(peaks_list, pre_window).float()   # [T_cal,F]
        tmask = torch.zeros(self.N, dtype=torch.bool, device=self.device)
        tmask[peaks] = True                                            # damage measured on peak windows
        peak_nse_clean = self._peak_nse(self._preds(self.zero), peaks)
        g0 = torch.Generator(device=self.device).manual_seed(seed)
        init = torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)
        delta = _clamp(_tie_copy(init) * pmask, eps)                   # zero outside pre-event set
        best_pn, best_delta = peak_nse_clean, self.zero               # include "do nothing" baseline
        pn0 = self._peak_nse(self._preds(delta), peaks)
        if pn0 < best_pn:
            best_pn, best_delta = pn0, delta
        alpha = 2 * eps
        for t in range(n_iter):
            g = _tie_grad(self._grad_masked(delta, tmask)) * pmask     # restrict gradient to pre-event
            delta = _clamp(delta + alpha * g.sign() * pmask, eps)
            pn = self._peak_nse(self._preds(delta), peaks)
            if pn < best_pn:
                best_pn, best_delta = pn, delta
            if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
                alpha *= 0.5
        return dict(D_peak=peak_nse_clean - best_pn,
                    D_overall=self.nse_clean - self.nse(best_delta),
                    n_peaks=len(peaks_list))

    # --- C&W (Exp5): minimum L2 perturbation to drive last-step NSE below target ---
    def _max_damage_within(self, r: float, radius_iters: int, step_frac: float) -> tuple:
        """L2-PGD: maximize damage (ss_res, i.e. minimize NSE) within ‖delta_cal‖₂ <= r.
        Ascends the chunked ss_res gradient, projects onto the L2 ball, temp-ties. Returns
        (nse_at_best, l2_at_best). Memory-bounded (reuses self.grad / self.nse)."""
        delta = torch.zeros(self.T_cal, self.F, device=self.device)
        step = step_frac * r
        best_nse, best_delta = self.nse_clean, delta
        for _ in range(radius_iters):
            g = _tie_grad(self.grad(delta))                # ∂(ss_res/ss_tot)/∂δ; ascend to add damage
            delta = delta + step * g / g.norm().clamp(min=1e-12)
            dn = delta.norm()
            if dn > r:
                delta = delta * (r / dn)                   # project onto the L2 ball
            delta = _tie_copy(delta)
            cur = self.nse(delta)
            if cur < best_nse:
                best_nse, best_delta = cur, delta
        return best_nse, float(best_delta.norm())

    def cw_min_l2(self, target_nse: float = 0.0, radius_iters: int = 20, bisect_steps: int = 7,
                  r_hi: float = 10.0, step_frac: float = 0.25, seed: int = 0) -> dict:
        """Minimum ‖delta_cal‖₂ (standardized) to drive last-step NSE < target_nse, via bisection
        on the L2 radius r: for each r, maximize damage within ‖delta‖₂<=r (L2-PGD) and test
        whether NSE crosses the target. The smallest breaking r is the per-basin safety margin.
        Well-conditioned and memory-bounded; temperature-tied (Maurer)."""
        nse_hi, _ = self._max_damage_within(r_hi, radius_iters, step_frac)
        if nse_hi > target_nse:                            # not breakable within the search budget
            return dict(l2=float("nan"), success=False, nse_adv=nse_hi)
        r_lo, r_cur = 0.0, r_hi
        best_r, best_nse = r_hi, nse_hi
        for _ in range(bisect_steps):
            r_mid = 0.5 * (r_lo + r_cur)
            nse_mid, _ = self._max_damage_within(r_mid, radius_iters, step_frac)
            if nse_mid <= target_nse:                      # breaks -> try a smaller radius
                best_r, best_nse = r_mid, nse_mid
                r_cur = r_mid
            else:                                          # doesn't break -> need a larger radius
                r_lo = r_mid
        return dict(l2=best_r, success=True, nse_adv=best_nse)
