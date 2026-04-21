"""经典新安江模型核心计算函数（NumPy 矢量化版本）。

移植自 forecast_system_lite/src/kernels/core/hydro_model/process_model/xinanjiang/numpy/
保持原始实现不变。

状态向量: [w, wu, wl, wd, s, qs, qi, qg]
  w   - 总土壤水量 (mm)
  wu  - 上层土壤水量 (mm)
  wl  - 中层土壤水量 (mm)
  wd  - 深层土壤水量 (mm)
  s   - 自由水蓄水量 (mm)
  qs  - 地表径流汇流储量 (mm)
  qi  - 壤中流汇流储量 (mm)
  qg  - 地下径流汇流储量 (mm)
"""
import numpy as np


def redistribute_soil_water(
    w: np.ndarray,
    wu: np.ndarray,
    wl: np.ndarray,
    wd: np.ndarray,
    wm: np.ndarray,
    wum: np.ndarray,
    wlm: np.ndarray,
    wdm: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    将多余水量在三层土壤含水量 wu、wl、wd 之间重新分配（矢量化版本）。
    """
    # 1) 将 w 限制在 [0, wm] 内
    w = np.clip(w, 0.0, wm)

    # 2) 计算剩余水量 (可能为正，也可能为负)
    water_extra = w - (wu + wl + wd)

    # 3) 针对 water_extra > 1e-4 的成员，依次向 wu, wl, wd 填充
    mask_pos = (water_extra > 1e-4)
    if np.any(mask_pos):
        possible = (wum[mask_pos] - wu[mask_pos])
        take = np.minimum(water_extra[mask_pos], possible)
        wu[mask_pos] += take
        water_extra[mask_pos] -= take

        possible = (wlm[mask_pos] - wl[mask_pos])
        take = np.minimum(water_extra[mask_pos], possible)
        wl[mask_pos] += take
        water_extra[mask_pos] -= take

        possible = (wdm[mask_pos] - wd[mask_pos])
        take = np.minimum(water_extra[mask_pos], possible)
        wd[mask_pos] += take
        water_extra[mask_pos] -= take

    # 4) 针对 water_extra < -1e-4 的成员，需要从 wu, wl, wd 中依次回补
    mask_neg = (water_extra < -1e-4)
    if np.any(mask_neg):
        possible = wu[mask_neg]
        take = np.minimum(-water_extra[mask_neg], possible)
        wu[mask_neg] -= take
        water_extra[mask_neg] += take

        possible = wl[mask_neg]
        take = np.minimum(-water_extra[mask_neg], possible)
        wl[mask_neg] -= take
        water_extra[mask_neg] += take

        possible = wd[mask_neg]
        take = np.minimum(-water_extra[mask_neg], possible)
        wd[mask_neg] -= take
        water_extra[mask_neg] += take

    # 5) 再次将三层含水量限制在 [0, 各自容量] 内
    wu = np.clip(wu, 0.0, wum)
    wl = np.clip(wl, 0.0, wlm)
    wd = np.clip(wd, 0.0, wdm)

    return w, wu, wl, wd


def calc_runoff(
    w: np.ndarray,
    wmm: np.ndarray,
    wm: np.ndarray,
    b: np.ndarray,
    pe: np.ndarray
) -> np.ndarray:
    """
    蓄满产流 B 曲线计算。

    runoff = pe + w - wm + wm * (1 - (pe + w_temp)/wmm)^(1+b)   (未饱和)
    runoff = pe + w - wm                                          (饱和)
    """
    wm_safe = np.clip(wm, 1e-12, None)
    frac = np.clip(1 - w / wm_safe, 0.0, 1.0)
    w_temp = wmm * (1 - frac ** (1 / (1 + b)))

    runoff = np.zeros_like(pe)
    mask_pe_pos = (pe > 0)
    if np.any(mask_pe_pos):
        mask1 = mask_pe_pos & ((w_temp + pe) <= wmm)
        if np.any(mask1):
            runoff[mask1] = (
                pe[mask1]
                + w[mask1]
                - wm[mask1]
                + wm[mask1] * (
                    1 - (pe[mask1] + w_temp[mask1]) / wmm[mask1]
                ) ** (1 + b[mask1])
            )
        mask2 = mask_pe_pos & (~mask1)
        if np.any(mask2):
            runoff[mask2] = pe[mask2] + w[mask2] - wm[mask2]

    return runoff


def update_soil_layers(
    wu: np.ndarray,
    wl: np.ndarray,
    wd: np.ndarray,
    runoff: np.ndarray,
    rain: np.ndarray,
    ep: np.ndarray,
    wum: np.ndarray,
    wlm: np.ndarray,
    wdm: np.ndarray,
    c: np.ndarray
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    三层蒸散发计算 + 土壤水更新。

    返回: (w, new_wu, new_wl, new_wd, e)
    """
    pe = rain - ep
    water_extra = np.maximum(pe - runoff, 0.0)

    N = len(pe)
    eu = np.zeros(N, dtype=pe.dtype)
    el = np.zeros(N, dtype=pe.dtype)
    ed = np.zeros(N, dtype=pe.dtype)

    new_wu = np.copy(wu)
    new_wl = np.copy(wl)
    new_wd = np.copy(wd)

    # 分支1：pe > 0  (净入水)
    mask_pos = (pe > 0)
    if np.any(mask_pos):
        idx_pos = np.where(mask_pos)[0]
        eu[idx_pos] = ep[idx_pos]

        # 上层分配
        wu_plus = new_wu[idx_pos] + water_extra[idx_pos]
        over_mask_1 = (wu_plus > wum[idx_pos])
        idx_over1 = idx_pos[over_mask_1]
        idx_noover1 = idx_pos[~over_mask_1]

        new_wu[idx_over1] = wum[idx_over1]
        new_wu[idx_noover1] = wu_plus[~over_mask_1]

        water_extra_1 = np.zeros_like(wu_plus)
        water_extra_1[over_mask_1] = wu_plus[over_mask_1] - wum[idx_pos][over_mask_1]

        # 中层分配
        wl_plus = new_wl[idx_pos] + water_extra_1
        over_mask_2 = (wl_plus > wlm[idx_pos])
        idx_over2 = idx_pos[over_mask_2]
        idx_noover2 = idx_pos[~over_mask_2]

        new_wl[idx_over2] = wlm[idx_over2]
        new_wl[idx_noover2] = wl_plus[~over_mask_2]

        water_extra_2 = np.zeros_like(wl_plus)
        water_extra_2[over_mask_2] = wl_plus[over_mask_2] - wlm[idx_pos][over_mask_2]

        # 深层分配
        wd_plus = new_wd[idx_pos] + water_extra_2
        over_mask_3 = (wd_plus > wdm[idx_pos])
        idx_over3 = idx_pos[over_mask_3]
        idx_noover3 = idx_pos[~over_mask_3]

        new_wd[idx_over3] = wdm[idx_over3]
        new_wd[idx_noover3] = wd_plus[~over_mask_3]

    # 分支2：pe <= 0 (净蒸发消耗)
    mask_neg = (pe <= 0)
    if np.any(mask_neg):
        # 2.1) wu + rain > ep
        cond = (new_wu[mask_neg] + rain[mask_neg]) > ep[mask_neg]
        idxA = np.where(mask_neg & cond)[0]
        if idxA.size > 0:
            eu[idxA] = ep[idxA]
            new_wu[idxA] = new_wu[idxA] + pe[idxA]

        # 2.2) wu + rain <= ep
        idxB = np.where(mask_neg & ~cond)[0]
        if idxB.size > 0:
            eu[idxB] = new_wu[idxB] + rain[idxB]
            new_wu[idxB] = 0.0

            remainder = ep[idxB] - eu[idxB]

            # (a) wl >= c * wlm
            condA = (new_wl[idxB] >= c[idxB] * wlm[idxB])
            idxA2 = idxB[condA]
            if idxA2.size > 0:
                el[idxA2] = np.abs(remainder[condA] * new_wl[idxA2] / wlm[idxA2])
                new_wl[idxA2] = new_wl[idxA2] - el[idxA2]

            # (b) wl >= c * (ep - eu)
            condB = ~condA & (new_wl[idxB] >= c[idxB] * np.abs(remainder))
            idxB2 = idxB[condB]
            if idxB2.size > 0:
                el[idxB2] = c[idxB2] * np.abs(remainder[condB])
                new_wl[idxB2] = new_wl[idxB2] - el[idxB2]

            # (c) else
            idxC2 = idxB[~condA & ~condB]
            if idxC2.size > 0:
                el[idxC2] = new_wl[idxC2]
                new_wl[idxC2] = 0.0
                ed[idxC2] = np.abs(c[idxC2] * remainder[~condA & ~condB] - el[idxC2])
                new_wd[idxC2] = new_wd[idxC2] - ed[idxC2]

    new_wu = np.clip(new_wu, 0, wum)
    new_wl = np.clip(new_wl, 0, wlm)
    new_wd = np.clip(new_wd, 0, wdm)

    w = new_wu + new_wl + new_wd
    e = eu + el + ed

    return w, new_wu, new_wl, new_wd, e


def update_soil_moisture(
    wu: np.ndarray,
    wl: np.ndarray,
    wd: np.ndarray,
    rain: np.ndarray,
    ep: np.ndarray,
    wmm: np.ndarray,
    wm: np.ndarray,
    b: np.ndarray,
    wum: np.ndarray,
    wlm: np.ndarray,
    wdm: np.ndarray,
    c: np.ndarray
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    主函数：先产流 (calc_runoff)，再更新土壤层 (update_soil_layers)。

    返回: (w_new, wu_new, wl_new, wd_new, runoff, e)
    """
    pe = rain - ep
    runoff = calc_runoff(wu + wl + wd, wmm, wm, b, pe)
    w_new, wu_new, wl_new, wd_new, e = update_soil_layers(
        wu, wl, wd, runoff, rain, ep, wum, wlm, wdm, c)
    return w_new, wu_new, wl_new, wd_new, runoff, e


def update_free_water_storage(
        s: np.ndarray,
        runoff: np.ndarray,
        pe: np.ndarray,
        ki: np.ndarray,
        kg: np.ndarray,
        ms: np.ndarray,
        sm: np.ndarray,
        ex: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    自由水蓄水库 — 三水源划分 (rs/ri/rg)。

    返回: (s_new, rs, ri, rg, fr)
    """
    s_new = np.copy(s)

    # 与 forecast_system_lite 生产版本一致：无条件削减
    s_new = np.minimum(sm, s_new)
    s_new = s_new * (1 - ki - kg)

    # s_temp
    sm_safe = np.clip(sm, 1e-12, None)
    frac = np.clip(1 - s_new / sm_safe, 0.0, 1.0)
    s_temp = ms * (1 - frac ** (1 / (1 + ex)))

    # fr = min(1, runoff/pe) if runoff>0, else 0
    fr = np.zeros_like(pe)
    mask_runoff_pos = (runoff > 0)
    if np.any(mask_runoff_pos):
        ratio = np.zeros_like(pe)
        mask_pe_pos = (pe > 1e-12)
        valid_mask = mask_runoff_pos & mask_pe_pos
        ratio[valid_mask] = runoff[valid_mask] / pe[valid_mask]
        fr[valid_mask] = np.minimum(1.0, ratio[valid_mask])
        fr[mask_runoff_pos & (~mask_pe_pos)] = 0

    # 计算表面流 rs
    rs = np.zeros_like(pe)
    if np.any(mask_runoff_pos):
        mask_cond1 = mask_runoff_pos & ((pe + s_temp) < ms)
        if np.any(mask_cond1):
            rs[mask_cond1] = (
                    fr[mask_cond1]
                    * (
                            (pe[mask_cond1] + s_new[mask_cond1])
                            - sm[mask_cond1]
                            + sm[mask_cond1]
                            * (
                                    1 - ((pe[mask_cond1] + s_temp[mask_cond1]) / ms[mask_cond1])
                            ) ** (1 + ex[mask_cond1])
                    )
            )
        mask_cond2 = mask_runoff_pos & (~mask_cond1)
        if np.any(mask_cond2):
            rs[mask_cond2] = fr[mask_cond2] * (pe[mask_cond2] + s_new[mask_cond2] - sm[mask_cond2])

        if not np.all(np.isreal(rs)):
            raise ValueError("r_surface is not real")

        # 更新 s
        s_add = np.copy(s_new)
        mask_fr_positive = (fr > 1e-12)
        ratio_rs = np.zeros_like(rs)
        valid_fr_mask = mask_fr_positive & mask_runoff_pos
        ratio_rs[valid_fr_mask] = rs[valid_fr_mask] / fr[valid_fr_mask]

        s_add[mask_runoff_pos] = s_new[mask_runoff_pos] + pe[mask_runoff_pos] - ratio_rs[mask_runoff_pos]
        s_add = np.clip(s_add, 0, sm)
        s_new = s_add
    else:
        rs[:] = 0
        s_new = np.minimum(sm, s_new)
        s_new = np.maximum(0, s_new)

    # ri = ki*s*fr, rg = kg*s*fr
    ri = ki * s_new * fr
    rg = kg * s_new * fr

    return s_new, rs, ri, rg, fr


def update_qs_qi_qg(
        qs: np.ndarray,
        qi: np.ndarray,
        qg: np.ndarray,
        rs: np.ndarray,
        ri: np.ndarray,
        rg: np.ndarray,
        cs: np.ndarray,
        ci: np.ndarray,
        cg: np.ndarray,
        uf: np.ndarray
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    三段汇流（线性水库）。

    qs_new = cs * qs + (1 - cs) * rs * uf
    qi_new = ci * qi + (1 - ci) * ri * uf
    qg_new = cg * qg + (1 - cg) * rg * uf
    """
    qs_new = cs * qs + (1 - cs) * rs * uf
    qi_new = ci * qi + (1 - ci) * ri * uf
    qg_new = cg * qg + (1 - cg) * rg * uf
    return qs_new, qi_new, qg_new


def _get_param(param_value):
    """智能获取 numpy 数组参数（兼容 DataFrame/Series/直接数组）。"""
    if isinstance(param_value, np.ndarray):
        return param_value
    elif hasattr(param_value, 'to_numpy'):
        return param_value.to_numpy()
    else:
        return np.array(param_value)


def xaj_step_vec(
        state: np.ndarray,
        rain: np.ndarray,
        pet: np.ndarray,
        param_dict: dict
) -> np.ndarray:
    """
    XAJ 单步计算（矢量化并行版）。

    state: shape (N, 8) — [w, wu, wl, wd, s, qs, qi, qg]
    rain, pet: shape (N,)
    param_dict: 所有参数的 dict, 每个键为 shape (N,) 数组

    Returns: new_state shape (N, 8)
    """
    # 从 state 拆分
    w = state[:, 0]
    wu = state[:, 1]
    wl = state[:, 2]
    wd = state[:, 3]
    s = state[:, 4]
    qs = state[:, 5]
    qi = state[:, 6]
    qg = state[:, 7]

    # 从 param_dict 按名称取
    kc = _get_param(param_dict["kc"])
    ki = _get_param(param_dict["ki"])
    kg = _get_param(param_dict["kg"])
    cs = _get_param(param_dict["cs"])
    ci_ = _get_param(param_dict["ci"])
    cg_ = _get_param(param_dict["cg"])
    wum = _get_param(param_dict["wum"])
    wlm = _get_param(param_dict["wlm"])
    wdm = _get_param(param_dict["wdm"])
    sm = _get_param(param_dict["sm"])
    imp = _get_param(param_dict["imp"])
    c = _get_param(param_dict["c"])
    b = _get_param(param_dict["b"])
    ex = _get_param(param_dict["ex"])
    uf = _get_param(param_dict["uf"])
    wmm = _get_param(param_dict["wmm"])
    ms = _get_param(param_dict["ms"])
    wm = wum + wlm + wdm

    # 计算
    ep = kc * pet
    pe = rain - ep

    w, wu, wl, wd = redistribute_soil_water(w, wu, wl, wd, wm, wum, wlm, wdm)
    w, wu, wl, wd, runoff, e = update_soil_moisture(
        wu, wl, wd, rain, ep, wmm, wm, b, wum, wlm, wdm, c)
    s, rs, ri, rg, fr = update_free_water_storage(
        s, runoff, pe, ki, kg, ms, sm, ex)
    qs, qi, qg = update_qs_qi_qg(qs, qi, qg, rs, ri, rg, cs, ci_, cg_, uf)

    new_state = np.column_stack([w, wu, wl, wd, s, qs, qi, qg])
    return new_state
