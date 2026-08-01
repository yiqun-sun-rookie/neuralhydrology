import csv
import hashlib
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_maurer(path: Path, *, tmax_equals_tmin: bool = True) -> None:
    rows = [
        " 44.0\n",
        " 133.0\n",
        " 1000000\n",
        "Year Mnth Day Hr Dayl(s) PRCP(mm/day) SRAD(W/m2) SWE(mm) Tmax(C) Tmin(C) Vp(Pa)\n",
    ]
    for index, date in enumerate(pd.date_range("2000-01-01", "2000-01-04", freq="D")):
        tmax = 2.0 + index
        tmin = tmax if tmax_equals_tmin else tmax - 1.0
        rows.append(
            f"{date.year} {date.month:02d} {date.day:02d} 12 100.0 {index + 0.5} {20 + index}.0 0.0 {tmax} {tmin} {300 + index}.0\n"
        )
    path.write_text("".join(rows), encoding="utf-8")


def test_maurer_reader_enforces_hash_period_columns_and_temperature_report(tmp_path):
    from formal_input_sources_v09 import read_maurer_window_v09

    path = tmp_path / "basin.txt"
    _write_maurer(path)
    values, report = read_maurer_window_v09(
        path,
        expected_sha256=_sha(path),
        expected_dates=pd.date_range("2000-01-02", "2000-01-04", freq="D"),
    )
    assert values.shape == (3, 5)
    assert values.dtype == np.float32
    np.testing.assert_allclose(values[0], [1.5, 3.0, 3.0, 21.0, 301.0])
    assert report["tmin_equals_tmax_rows"] == 3

    with pytest.raises(ValueError, match="SHA-256"):
        read_maurer_window_v09(
            path,
            expected_sha256="0" * 64,
            expected_dates=pd.date_range("2000-01-02", "2000-01-04", freq="D"),
        )


def test_static_loader_uses_alphabetical_float64_ddof1_then_float32(tmp_path):
    from data import STATIC_COLUMNS
    from formal_input_contract_v09 import FORMAL_V09_STATIC_COLUMNS
    from formal_input_sources_v09 import load_static_arrays_v09

    basins = ("00000001", "00000002", "00000003")
    frame = pd.DataFrame({"gauge_id": basins})
    for column_index, column in enumerate(STATIC_COLUMNS):
        frame[column] = np.asarray([1.0, 3.0, 5.0]) + column_index
    path = tmp_path / "statics.csv"
    frame.to_csv(path, index=False)
    raw, normalized, scaler = load_static_arrays_v09(
        path,
        expected_sha256=_sha(path),
        basins=basins,
    )
    assert raw.dtype == np.float64
    assert normalized.dtype == np.float32
    assert raw.shape == (3, 27)
    np.testing.assert_allclose(scaler["center"], raw.mean(axis=0, dtype=np.float64))
    np.testing.assert_allclose(scaler["scale"], raw.std(axis=0, ddof=1, dtype=np.float64))
    np.testing.assert_allclose(normalized[:, 0], [-1.0, 0.0, 1.0])

    reordered = tmp_path / "statics_reordered.csv"
    frame.loc[:, ["gauge_id", *reversed(STATIC_COLUMNS)]].to_csv(reordered, index=False)
    with pytest.raises(ValueError, match="source-column order"):
        load_static_arrays_v09(
            reordered,
            expected_sha256=_sha(reordered),
            basins=basins,
        )


def test_target_streamer_requires_exact_order_and_range(tmp_path):
    from formal_input_sources_v09 import write_target_array_v09

    basins = ("00000001", "00000002")
    dates = pd.date_range("2000-01-01", "2000-01-03", freq="D")
    source = tmp_path / "targets.csv"
    with source.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(("basin", "date", "qobs"))
        for basin_index, basin in enumerate(basins):
            for date_index, date in enumerate(dates):
                writer.writerow((basin, date.strftime("%Y-%m-%d"), basin_index + date_index / 10))
    output = tmp_path / "targets.npy"
    report = write_target_array_v09(
        source,
        expected_sha256=_sha(source),
        basins=basins,
        expected_dates=dates,
        output_path=output,
    )
    values = np.load(output, allow_pickle=False)
    assert values.shape == (2, 3) and values.dtype == np.float32
    assert report["row_count"] == 6

    bad = tmp_path / "bad.csv"
    text = source.read_text(encoding="utf-8").replace("00000001,2000-01-02", "00000002,2000-01-02")
    bad.write_text(text, encoding="utf-8")
    with pytest.raises(ValueError, match="order"):
        write_target_array_v09(
            bad,
            expected_sha256=_sha(bad),
            basins=basins,
            expected_dates=dates,
            output_path=tmp_path / "bad.npy",
        )


def test_forcing_writer_uses_manifest_paths_and_one_basin_chunks(tmp_path):
    from formal_input_sources_v09 import write_forcing_array_v09

    data_root = tmp_path / "data"
    data_root.mkdir()
    sources = []
    for index, basin in enumerate(("00000001", "00000002")):
        path = data_root / f"{basin}.txt"
        _write_maurer(path)
        sources.append({"basin": basin, "relative_path": path.name, "sha256": _sha(path)})
    checkpoints = []
    output = tmp_path / "forcing.npy"
    report = write_forcing_array_v09(
        data_root=data_root,
        sources=sources,
        basins=("00000001", "00000002"),
        expected_dates=pd.date_range("2000-01-01", "2000-01-04", freq="D"),
        output_path=output,
        checkpoint=lambda: checkpoints.append(True),
    )
    assert np.load(output, mmap_mode="r", allow_pickle=False).shape == (2, 4, 5)
    assert len(checkpoints) == 3
    assert report["tmin_equals_tmax_rows"] == 8
