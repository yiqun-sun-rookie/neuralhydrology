import pytest
import pandas as pd
import numpy as np
from pathlib import Path
import tempfile
import os


class TestBasinSelection:

    def test_select_representative_synthetic(self, tmp_path):
        """Test basin selection with synthetic attribute data."""
        from src.adversarial.evaluation.basin_selection import select_representative_basins

        rng = np.random.RandomState(42)
        n = 50
        df = pd.DataFrame({
            "gauge_id": [f"{i:08d}" for i in range(n)],
            "gauge_elev_mean": rng.randn(n),
            "gauge_slope_mean": rng.randn(n),
            "area": rng.rand(n) * 1000,
            "p_mean": rng.rand(n) * 5,
            "aridity": rng.rand(n) * 3,
            "frac_snow": rng.rand(n),
            "frac_forest": rng.rand(n),
            "soil_depth_pelletier": rng.rand(n) * 10,
        })

        csv_path = tmp_path / "attrs.csv"
        df.to_csv(csv_path, index=False)

        basins = select_representative_basins(attr_file=csv_path, n_basins=10)
        assert len(basins) == 10
        assert all(isinstance(b, str) for b in basins)
        assert all(len(b) == 8 for b in basins)
        assert len(set(basins)) == 10
