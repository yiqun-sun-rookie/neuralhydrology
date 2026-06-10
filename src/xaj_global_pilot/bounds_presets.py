"""Named PDD+XAJ parameter-bound presets for the calibration playbook.

The HBV-lite playbook found that bounds widening only helps when calibration is
*saturating* against a ceiling (technique 3: bounds<->PET coupling). To apply
the same lever to XAJ we keep the current bounds as ``v1`` and add widened
presets that are switched on only after a saturation audit shows a parameter
pinned at its bound for a meaningful fraction of basins.

``resolve_xaj_bounds`` merges PDD + XAJ defaults, then applies preset overrides,
preserving the 20-parameter ordering of ``PDD_XAJ_PARAM_NAMES``.
"""
from __future__ import annotations


# Per-preset overrides. Empty dict => use defaults verbatim.
# Keys must match parameter names in PDD_PARAM_BOUNDS / PARAM_BOUNDS.
_PRESET_OVERRIDES: dict[str, dict[str, tuple[float, float]]] = {
    "v1": {},  # current defaults (xaj_model.PARAM_BOUNDS / PDD_PARAM_BOUNDS)
    # v2_wide: widen the @hi pins from the iter0 saturation audit that are
    # physically defensible and impactful. The dominant one is kc — corrected
    # Oudin is only ~0.43x pet_mean, so 23% of basins pin kc at 1.8 (PET-starved).
    # Letting kc reach ~3.0 = allowing calibration to recover realistic PET.
    # wum/cg/ci pinned high => deeper upper storage / slower recession headroom.
    "v2_wide": {
        "kc":  (0.3, 3.0),     # PET scaling: relieve PET starvation (was 1.8)
        "wum": (2.0, 200.0),   # upper soil storage (was 120)
        "ci":  (0.3, 0.99),    # interflow recession (was 0.95)
        "cg":  (0.5, 0.9995),  # groundwater recession (was 0.998)
    },
    # v3_wide: the COMPLETE widening — every param flagged >=20% pinned in the
    # FINAL-531 saturation audit, BOTH @hi and the @lo pins that v2_wide missed
    # (temp_snow 41%, ex 27%, wdm 21%). imp@lo 42% is skipped: it pins at the
    # physical floor (~0 impervious), so widening it is a no-op.
    "v3_wide": {
        "kc":            (0.3, 3.0),      # @hi 35%
        "ci":            (0.3, 0.99),     # @hi 31%
        "cg":            (0.5, 0.9995),   # @hi 28%
        "wum":           (2.0, 200.0),    # @hi 27%
        "refreeze_snow": (0.0, 0.8),      # @hi 23% (physical <=1)
        "temp_snow":     (-5.0, 1.0),     # @lo 41% (all-snow threshold)
        "ex":            (0.01, 4.0),     # @lo 27% (free-water curve exponent)
        "wdm":           (0.5, 150.0),    # @lo 21% (deep soil storage)
    },
}


def list_presets() -> list[str]:
    return sorted(_PRESET_OVERRIDES)


def register_preset(name: str, overrides: dict[str, tuple[float, float]]) -> None:
    """Register a new bounds preset at runtime (used after a saturation audit)."""
    _PRESET_OVERRIDES[name] = dict(overrides)


def resolve_xaj_bounds(preset: str, pdd_bounds: dict, xaj_bounds: dict) -> dict:
    """Return the merged 20-parameter bounds dict for ``preset``.

    Parameters
    ----------
    preset : str
        Key into the preset table. ``v1`` reproduces the current defaults.
    pdd_bounds, xaj_bounds : dict
        ``PDD_PARAM_BOUNDS`` and ``PARAM_BOUNDS`` from ``xaj_model``.
    """
    if preset not in _PRESET_OVERRIDES:
        raise ValueError(f"Unknown bounds preset {preset!r}. Known: {list_presets()}")
    merged = {**pdd_bounds, **xaj_bounds}
    for name, rng in _PRESET_OVERRIDES[preset].items():
        if name not in merged:
            raise KeyError(f"Preset {preset!r} overrides unknown param {name!r}")
        merged[name] = tuple(rng)
    return merged
