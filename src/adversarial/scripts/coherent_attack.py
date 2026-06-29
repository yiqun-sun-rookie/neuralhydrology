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

    def apgd_targeted(self, eps: float, target: str, n_iter: int = 50, seed: int = 0) -> float:
        """APGD optimizing damage on the target-day subset; reports OVERALL damage D=nse_clean-nse_adv."""
        tmask = self._flow_mask(target)
        g0 = torch.Generator(device=self.device).manual_seed(seed)
        delta = _clamp(_tie_copy(torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)), eps)
        best = self.nse(delta)
        alpha = 2 * eps
        for t in range(n_iter):
            g = _tie_grad(self._grad_masked(delta, tmask))
            delta = _clamp(delta + alpha * g.sign(), eps)
            cur = self.nse(delta)            # OVERALL nse (untargeted metric), so flood vs lowflow is comparable
            if cur < best:
                best = cur
            if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
                alpha *= 0.5
        return self.nse_clean - best

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
