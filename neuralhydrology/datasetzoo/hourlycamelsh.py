"""CAMELS-H hourly dataset class for NeuralHydrology.

Data layout expected at data_dir (= data/camelsh/):
  timeseries/Data/CAMELSH/timeseries/{basin}.nc  # Tair, Rainf, Streamflow, DateTime dim
  attributes/attributes.csv                       # basin_id (int), elev_mean, slope_mean, area(km²)...
"""
import logging
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd
import xarray as xr

from neuralhydrology.datasetzoo.basedataset import BaseDataset
from neuralhydrology.utils.config import Config

LOGGER = logging.getLogger(__name__)

_TIMESERIES_SUBPATH = Path("timeseries/Data/CAMELSH/timeseries")
_ATTRIBUTES_FILE = Path("attributes/attributes.csv")


class HourlyCamelsH(BaseDataset):
    """Hourly CAMELS-H dataset class.

    Reads per-basin hourly NetCDF files containing ERA5-Land forcings and USGS streamflow.
    Streamflow is converted from m³/s to mm/hr using the basin area from the attributes file.

    Parameters
    ----------
    cfg : Config
        Run configuration. Key fields:
        - ``data_dir``: path to ``data/camelsh/``
        - ``dynamic_inputs``: subset of ``['Rainf', 'Tair', 'PSurf', 'SWdown', ...]``
        - ``target_variables``: should include ``'qobs_mm_per_hour'``
        - ``static_attributes``: subset of columns in ``attributes/attributes.csv``
    is_train : bool
        Defines if the dataset is used for training or evaluating. If True (training), means/stds for each
        feature are computed and stored to the run directory. If one-hot encoding is used, the mapping for
        the one-hot encoding is created and also stored to disk. If False, a ``scaler`` input is expected
        and similarly the ``id_to_int`` input if one-hot encoding is used.
    period : {'train', 'validation', 'test'}
        Defines the period for which the data will be loaded.
    basin : str, optional
        If passed, the data for only this basin will be loaded. Otherwise the basin(s) is(are) read from the
        appropriate basin file, corresponding to the ``period``.
    additional_features : List[Dict[str, pd.DataFrame]], optional
        List of dictionaries, mapping from a basin id to a pandas DataFrame. This DataFrame will be added to
        the data loaded from the dataset and all columns are available as 'dynamic_inputs',
        'evolving_attributes' and 'target_variables'.
    id_to_int : Dict[str, int], optional
        If the config argument 'use_basin_id_encoding' is True in the config and period is either
        'validation' or 'test', this input is required. It is a dictionary, mapping from basin id to an
        integer (the one-hot encoding).
    scaler : Dict[str, Union[pd.Series, xarray.DataArray]], optional
        If period is either 'validation' or 'test', this input is required. It contains the centering and
        scaling for each feature and is stored to the run directory during training
        (train_data/train_data_scaler.yml).
    """

    def __init__(self,
                 cfg: Config,
                 is_train: bool,
                 period: str,
                 basin: str = None,
                 additional_features: list = [],
                 id_to_int: dict = {},
                 scaler: dict = {}):
        self._attrs_cache: Optional[pd.DataFrame] = None
        super().__init__(cfg=cfg,
                         is_train=is_train,
                         period=period,
                         basin=basin,
                         additional_features=additional_features,
                         id_to_int=id_to_int,
                         scaler=scaler)

    def _load_basin_data(self, basin: str) -> pd.DataFrame:
        """Load hourly timeseries for one basin from CAMELS-H NetCDF.

        Parameters
        ----------
        basin : str
            8-digit basin identifier string (e.g. ``"03157000"``).

        Returns
        -------
        pd.DataFrame
            Time-indexed DataFrame with hourly forcings and ``qobs_mm_per_hour`` column.
            Index name is ``"date"``.
        """
        nc_path = self.cfg.data_dir / _TIMESERIES_SUBPATH / f"{basin}.nc"
        if not nc_path.is_file():
            raise FileNotFoundError(f"No CAMELS-H timeseries NC for basin {basin} at {nc_path}")

        ds = xr.open_dataset(nc_path)
        # The time dimension in CAMELS-H NetCDF files is named 'DateTime'
        if "DateTime" in ds.dims:
            df = ds.to_dataframe()
        else:
            df = ds.to_dataframe()
        df.index.name = "date"

        # Convert Streamflow m³/s → qobs_mm_per_hour mm/hr
        if "Streamflow" in df.columns:
            area_km2 = self._get_basin_area(basin)
            area_m2 = area_km2 * 1e6
            df["qobs_mm_per_hour"] = df["Streamflow"] * 3600.0 * 1000.0 / area_m2
            df.loc[df["qobs_mm_per_hour"] < 0, "qobs_mm_per_hour"] = np.nan

        return df

    def _get_basin_area(self, basin: str) -> float:
        """Return basin area in km² from the attributes file.

        Parameters
        ----------
        basin : str
            8-digit basin identifier string.

        Returns
        -------
        float
            Basin area in km².
        """
        attrs = self._get_attrs_cached()
        if basin not in attrs.index:
            raise KeyError(f"Basin {basin} not found in CAMELS-H attributes file")
        return float(attrs.loc[basin, "area"])

    def _get_attrs_cached(self) -> pd.DataFrame:
        """Return attributes DataFrame, loading from disk if not yet cached.

        Returns
        -------
        pd.DataFrame
            Attributes DataFrame indexed by 8-digit basin id strings.
        """
        if self._attrs_cache is None:
            self._attrs_cache = _load_camelsh_attributes(self.cfg.data_dir)
        return self._attrs_cache

    def _load_attributes(self) -> pd.DataFrame:
        """Return attributes DataFrame indexed by 8-digit basin id strings.

        Returns
        -------
        pd.DataFrame
            Static attributes for all basins, indexed by 8-digit basin id strings.
        """
        return _load_camelsh_attributes(self.cfg.data_dir)


def _load_camelsh_attributes(data_dir: Path) -> pd.DataFrame:
    """Load CAMELS-H attributes CSV, return DataFrame indexed by 8-digit basin id strings.

    Parameters
    ----------
    data_dir : Path
        Path to the CAMELS-H root directory (``data/camelsh/``).

    Returns
    -------
    pd.DataFrame
        Attributes DataFrame with index converted to zero-padded 8-character strings.

    Raises
    ------
    FileNotFoundError
        If the attributes CSV file does not exist at the expected location.
    """
    attrs_path = data_dir / _ATTRIBUTES_FILE
    if not attrs_path.is_file():
        raise FileNotFoundError(f"CAMELS-H attributes not found at {attrs_path}")
    attrs = pd.read_csv(attrs_path, index_col="basin_id")
    attrs.index = attrs.index.astype(str).str.zfill(8)
    return attrs
