import json
import hashlib
import os
from pathlib import Path

import pandas as pd
import pytest

from unified_autoresearch.selection.basins import APPROVED_STATIC_ATTRIBUTES


MODULE_ROOT = Path(__file__).resolve().parents[1]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_development_only_source(root: Path) -> Path:
    root.mkdir()
    basins = json.loads((MODULE_ROOT / "selection" / "development_basins_v1.json").read_text(encoding="utf-8"))[
        "basins"
    ]
    dates = pd.to_datetime(
        ["1999-10-01", "2002-09-30", "2002-10-01", "2005-09-30", "2005-10-01", "2008-09-30"]
    )
    feature_rows = []
    target_rows = []
    for basin_index, basin in enumerate(basins):
        for date_index, date in enumerate(dates):
            feature_rows.append(
                {
                    "basin": basin,
                    "date": date,
                    "prcp": float(date_index + 1),
                    "tmin": float(basin_index),
                    "tmax": float(basin_index + 10),
                    "srad": float(date_index + 100),
                    "vp": float(date_index + 1000),
                }
            )
            target_rows.append({"basin": basin, "date": date, "qobs": float(basin_index + date_index + 1)})
    pd.DataFrame(feature_rows).to_parquet(root / "features.parquet", index=False)
    pd.DataFrame(target_rows).to_parquet(root / "targets.parquet", index=False)
    static_attributes = {
        "schema_version": "development_static_attributes_v1",
        "basins": {
            basin: {name: float(basin_index + attribute_index + 1) for attribute_index, name in enumerate(APPROVED_STATIC_ATTRIBUTES)}
            for basin_index, basin in enumerate(basins)
        },
    }
    (root / "static_attributes.json").write_text(
        json.dumps(static_attributes, sort_keys=True), encoding="utf-8"
    )
    manifest_path = root / "SOURCE_MANIFEST.json"
    manifest_path.write_text(
        json.dumps(
            {
                "schema_version": "development_source_v1",
                "source_kind": "explicitly_pre_sliced_development_only",
                "forcing_product": "maurer",
                "date_bounds": ["1999-10-01", "2008-09-30"],
                "sealed_final_evaluation_present": False,
                "files": {
                    name: _sha256(root / name)
                    for name in ("features.parquet", "targets.parquet", "static_attributes.json")
                },
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    return manifest_path


def _refresh_source_manifest_hash(manifest_path: Path, filename: str) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["files"][filename] = _sha256(manifest_path.parent / filename)
    manifest_path.write_text(json.dumps(manifest, sort_keys=True), encoding="utf-8")


def test_data_builder_rejects_untrusted_date_bounds_before_opening_source_tables(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_root.mkdir()
    source_manifest = source_root / "SOURCE_MANIFEST.json"
    source_manifest.write_text(
        json.dumps(
            {
                "schema_version": "development_source_v1",
                "source_kind": "explicitly_pre_sliced_development_only",
                "forcing_product": "maurer",
                "date_bounds": ["1999-09-30", "2008-09-30"],
                "sealed_final_evaluation_present": False,
                "files": {
                    "features.parquet": "0" * 64,
                    "targets.parquet": "1" * 64,
                    "static_attributes.json": "2" * 64,
                },
            }
        ),
        encoding="utf-8",
    )

    output_root = tmp_path / "packages"
    with pytest.raises(ValueError, match="source date bounds must exactly match the development-only interval"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
            output_root=output_root,
        )

    assert not output_root.exists()


def test_data_builder_creates_only_two_isolated_development_protocol_packages(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    output_root = tmp_path / "packages"

    package_manifest = build_development_packages(
        source_root=source_root,
        source_manifest_path=source_manifest,
        protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
        selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
        output_root=output_root,
    )

    assert package_manifest["protocols"] == ["forward", "reverse"]
    assert {path.name for path in output_root.iterdir()} == {"forward", "reverse", "PACKAGE_MANIFEST.json"}
    for protocol_name in ("forward", "reverse"):
        protocol_root = output_root / protocol_name
        assert {path.name for path in protocol_root.iterdir()} == {"train", "predict", "score"}
        assert {path.name for path in (protocol_root / "train").iterdir()} == {
            "train_features.parquet",
            "train_targets.parquet",
            "static_attributes.json",
        }
        assert {path.name for path in (protocol_root / "predict").iterdir()} == {
            "predict_features.parquet",
            "static_attributes.json",
        }
        assert {path.name for path in (protocol_root / "score").iterdir()} == {"validation_truth.parquet"}
        prediction_columns = set(pd.read_parquet(protocol_root / "predict" / "predict_features.parquet").columns)
        assert prediction_columns == {"basin", "date", "prcp", "tmin", "tmax", "srad", "vp"}
        assert "qobs" not in prediction_columns
        assert set(pd.read_parquet(protocol_root / "score" / "validation_truth.parquet").columns) == {
            "basin",
            "date",
            "qobs",
        }


def test_data_builder_rejects_unapproved_static_attributes_before_creating_output(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    static_path = source_root / "static_attributes.json"
    statics = json.loads(static_path.read_text(encoding="utf-8"))
    for values in statics["basins"].values():
        values["q_mean"] = 1.0
    static_path.write_text(json.dumps(statics, sort_keys=True), encoding="utf-8")
    _refresh_source_manifest_hash(source_manifest, "static_attributes.json")
    output_root = tmp_path / "packages"

    with pytest.raises(ValueError, match="exactly 27 approved static attributes"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
            output_root=output_root,
        )

    assert not output_root.exists()


def test_data_builder_rejects_drifted_development_basin_selection(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    drifted_selection = tmp_path / "development_basins_drifted.json"
    selection = json.loads((MODULE_ROOT / "selection" / "development_basins_v1.json").read_text(encoding="utf-8"))
    selection["selection_method"] = "unapproved_method"
    drifted_selection.write_text(json.dumps(selection), encoding="utf-8")

    with pytest.raises(ValueError, match="frozen development basin selection mismatch"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=drifted_selection,
            output_root=tmp_path / "packages",
        )


def test_data_builder_rejects_nonfinite_static_values(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    static_path = source_root / "static_attributes.json"
    statics = json.loads(static_path.read_text(encoding="utf-8"))
    first_basin = next(iter(statics["basins"]))
    statics["basins"][first_basin][APPROVED_STATIC_ATTRIBUTES[0]] = float("nan")
    static_path.write_text(json.dumps(statics, sort_keys=True), encoding="utf-8")
    _refresh_source_manifest_hash(source_manifest, "static_attributes.json")

    with pytest.raises(ValueError, match="static attributes must be finite numeric values"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
            output_root=tmp_path / "packages",
        )


@pytest.mark.parametrize(("filename", "column"), [("features.parquet", "prcp"), ("targets.parquet", "qobs")])
def test_data_builder_rejects_nonfinite_time_series_values(tmp_path, filename, column):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    table_path = source_root / filename
    frame = pd.read_parquet(table_path)
    frame.loc[0, column] = float("inf")
    frame.to_parquet(table_path, index=False)
    _refresh_source_manifest_hash(source_manifest, filename)

    with pytest.raises(ValueError, match="time-series values must be finite numbers"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
            output_root=tmp_path / "packages",
        )


def test_data_builder_rejects_duplicate_or_unmatched_basin_date_rows(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    feature_path = source_root / "features.parquet"
    features = pd.read_parquet(feature_path)
    pd.concat([features, features.iloc[[0]]], ignore_index=True).to_parquet(feature_path, index=False)
    _refresh_source_manifest_hash(source_manifest, "features.parquet")

    with pytest.raises(ValueError, match="unique basin-date rows and identical feature-target keys"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
            output_root=tmp_path / "packages",
        )


def test_data_builder_rejects_undeclared_files_in_dedicated_source_root(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    (source_root / "undeclared.bin").write_bytes(b"must not be silently ignored")

    with pytest.raises(ValueError, match="dedicated source root contains undeclared files"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
            output_root=tmp_path / "packages",
        )


def test_data_builder_rejects_linked_source_files(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    os.link(source_root / "features.parquet", tmp_path / "features-alias.parquet")

    with pytest.raises(ValueError, match="source files must be unlinked regular files"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
            output_root=tmp_path / "packages",
        )


def test_data_builder_rejects_matching_missing_dates_without_creating_output(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    for filename in ("features.parquet", "targets.parquet"):
        path = source_root / filename
        frame = pd.read_parquet(path)
        frame.loc[0, "date"] = pd.NaT
        frame.to_parquet(path, index=False)
        _refresh_source_manifest_hash(source_manifest, filename)
    output_root = tmp_path / "packages"

    with pytest.raises(ValueError, match="source dates must be present daily timestamps"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
            output_root=output_root,
        )

    assert not output_root.exists()


def test_data_builder_rejects_non_midnight_timestamps(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    source_root = tmp_path / "source"
    source_manifest = _write_development_only_source(source_root)
    for filename in ("features.parquet", "targets.parquet"):
        path = source_root / filename
        frame = pd.read_parquet(path)
        frame.loc[0, "date"] = frame.loc[0, "date"] + pd.Timedelta(hours=12)
        frame.to_parquet(path, index=False)
        _refresh_source_manifest_hash(source_manifest, filename)

    with pytest.raises(ValueError, match="source dates must be present daily timestamps"):
        build_development_packages(
            source_root=source_root,
            source_manifest_path=source_manifest,
            protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
            selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
            output_root=tmp_path / "packages",
        )
