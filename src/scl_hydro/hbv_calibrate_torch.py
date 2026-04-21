"""梯度优化率定 PyTorch HBV。

用 Adam + multi-restart 在可微分 HBV 上做参数优化，
对比 CMA-ES 等梯度无关方法的率定效果。
"""
import numpy as np
import torch

from .hbv_torch import DifferentiableHBV, PARAM_NAMES, PARAM_BOUNDS

WARMUP_DAYS = 365


def _nse_torch(obs: torch.Tensor, sim: torch.Tensor) -> torch.Tensor:
    """Differentiable NSE loss (returns 1 - NSE for minimization)."""
    mask = torch.isfinite(obs) & torch.isfinite(sim)
    if mask.sum() < 10:
        return torch.tensor(2.0)
    o = obs[mask]
    s = sim[mask]
    denom = ((o - o.mean()) ** 2).sum()
    if denom < 1e-12:
        return torch.tensor(2.0)
    return ((o - s) ** 2).sum() / denom


def calibrate_hbv_torch(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    obs: np.ndarray,
    n_epochs: int = 300,
    lr: float = 0.01,
    n_restarts: int = 5,
) -> dict:
    """Adam 多重启率定可微分 HBV。

    Parameters
    ----------
    n_epochs : 每次重启的优化步数
    lr : Adam 学习率
    n_restarts : 重启次数（不同随机初始化），取最优
    """
    warmup = min(WARMUP_DAYS, len(obs) // 4)

    # 准备 forcing tensor [1, T, 3]
    forcing = torch.tensor(
        np.stack([rain, pet, temp], axis=-1)[np.newaxis, :, :],
        dtype=torch.float32,
    )
    obs_tensor = torch.tensor(obs[warmup:], dtype=torch.float32)

    model = DifferentiableHBV()

    best_overall = None

    for restart in range(n_restarts):
        torch.manual_seed(restart * 1000 + 42)
        # 随机初始化 unconstrained 参数
        raw_params = torch.randn(1, 10, requires_grad=True)

        optimizer = torch.optim.Adam([raw_params], lr=lr)

        best_loss_this_restart = float('inf')
        best_raw_this_restart = None

        for epoch in range(n_epochs):
            optimizer.zero_grad()
            params = model.constrain_params(raw_params)
            q_sim, _, _ = model.forward(forcing, params)
            q_eval = q_sim[0, warmup:, 0]
            loss = _nse_torch(obs_tensor, q_eval)

            if not torch.isfinite(loss):
                break

            loss.backward()
            torch.nn.utils.clip_grad_norm_([raw_params], max_norm=10.0)
            optimizer.step()

            loss_val = loss.item()
            if loss_val < best_loss_this_restart:
                best_loss_this_restart = loss_val
                best_raw_this_restart = raw_params.detach().clone()

        if best_raw_this_restart is not None:
            if best_overall is None or best_loss_this_restart < best_overall[1]:
                best_overall = (best_raw_this_restart, best_loss_this_restart)

    if best_overall is None:
        return {'nse': -999.0, 'optimized_params': {}, 'qsim': np.zeros(len(obs)),
                'final_state': None}

    # 用最优参数跑最终模拟
    with torch.no_grad():
        params = model.constrain_params(best_overall[0])
        q_sim, _, states = model.forward(forcing, params)

    q_np = q_sim[0, :, 0].numpy()
    best_nse = 1.0 - best_overall[1]

    # 提取参数字典
    best_params = {}
    for i, name in enumerate(PARAM_NAMES):
        lo, hi = PARAM_BOUNDS[name]
        val = torch.sigmoid(best_overall[0][0, i]).item() * (hi - lo) + lo
        best_params[name] = val

    final_state = {
        'S_snow': states[0, -1, 0].item(),
        'S_soil': states[0, -1, 1].item(),
        'S_fast': states[0, -1, 2].item(),
        'S_slow': states[0, -1, 3].item(),
    }

    return {'nse': float(best_nse), 'optimized_params': best_params,
            'qsim': np.maximum(q_np, 0.0), 'final_state': final_state}
