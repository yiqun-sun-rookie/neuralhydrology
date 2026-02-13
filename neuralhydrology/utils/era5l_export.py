from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List


@dataclass(frozen=True)
class ExportConfig:
    """Configuration for exporting ERA5-Land data from Earth Engine."""

    mode: str
    dataset_id: str
    bands: List[str]
    date_format: str
    file_prefix: str
    accumulated_bands: List[str]


_EXPORT_CONFIGS: Dict[str, ExportConfig] = {
    "daily": ExportConfig(
        mode="daily",
        dataset_id="ECMWF/ERA5_LAND/DAILY_AGGR",
        bands=[
            "total_precipitation_sum",
            "surface_net_solar_radiation_sum",
            "surface_net_thermal_radiation_sum",
            "potential_evaporation_sum",
            "temperature_2m",
            "surface_pressure",
            "u_component_of_wind_10m",
            "v_component_of_wind_10m",
            "snow_depth_water_equivalent",
        ],
        date_format="yyyyMMdd",
        file_prefix="era5l_daily",
        accumulated_bands=[
            "total_precipitation_sum",
            "surface_net_solar_radiation_sum",
            "surface_net_thermal_radiation_sum",
            "potential_evaporation_sum",
        ],
    ),
    "hourly": ExportConfig(
        mode="hourly",
        dataset_id="ECMWF/ERA5_LAND/HOURLY",
        bands=[
            "total_precipitation",
            "surface_net_solar_radiation",
            "surface_net_thermal_radiation",
            "potential_evaporation",
            "temperature_2m",
            "dewpoint_temperature_2m",
            "surface_pressure",
            "u_component_of_wind_10m",
            "v_component_of_wind_10m",
            "snowfall",
        ],
        date_format="yyyyMMddHH",
        file_prefix="era5l_hourly",
        accumulated_bands=[
            "total_precipitation",
            "surface_net_solar_radiation",
            "surface_net_thermal_radiation",
            "potential_evaporation",
            "snowfall",
        ],
    ),
}


def get_export_config(mode: str) -> ExportConfig:
    """Return the export configuration for the requested mode.

    Parameters
    ----------
    mode : str
        Export mode. Supported values: ``"daily"`` (default), ``"hourly"``.

    Returns
    -------
    ExportConfig
        The configuration describing dataset ID, band selections, and metadata.

    Raises
    ------
    ValueError
        If ``mode`` is not supported.
    """

    normalized = mode.lower()
    if normalized not in _EXPORT_CONFIGS:
        raise ValueError(f"Unsupported export mode '{mode}'. Supported modes: {sorted(_EXPORT_CONFIGS.keys())}")
    return _EXPORT_CONFIGS[normalized]


__all__ = ["ExportConfig", "get_export_config"]


