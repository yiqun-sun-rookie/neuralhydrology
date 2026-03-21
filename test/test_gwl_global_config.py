from pathlib import Path

import pytest

from src.gwl_global.config import (
    PDOK_OGC_BASE,
    BRO_GLD_CSV_URL,
    KNMI_DAG_URL,
    NL_BBOX,
    KNMI_STATIONS,
    data_dir,
    knmi_station_for_coord,
)


def test_api_urls_are_strings():
    assert isinstance(PDOK_OGC_BASE, str)
    assert "api.pdok.nl" in PDOK_OGC_BASE
    assert isinstance(BRO_GLD_CSV_URL, str)
    assert isinstance(KNMI_DAG_URL, str)


def test_nl_bbox_has_four_floats():
    assert len(NL_BBOX) == 4
    min_lon, min_lat, max_lon, max_lat = NL_BBOX
    assert min_lon < max_lon
    assert min_lat < max_lat


def test_knmi_stations_have_required_fields():
    assert len(KNMI_STATIONS) >= 30
    for stn in KNMI_STATIONS:
        assert "stn" in stn
        assert "lat" in stn
        assert "lon" in stn
        assert "name" in stn


def test_knmi_station_for_coord():
    # De Bilt is at (52.10, 5.18), should match station 260
    stn = knmi_station_for_coord(52.10, 5.18)
    assert stn == 260


def test_data_dir_returns_path(tmp_path, monkeypatch):
    monkeypatch.setenv("GWL_DATA_DIR", str(tmp_path))
    d = data_dir()
    assert isinstance(d, Path)
