"""Candidate: classify original NoData in 12 fixed windows on HPC only."""
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import sys
import time
import traceback

ROOT = Path(__file__).resolve().parent
CONTEXT = {}


def sha_file(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for raw in iter(lambda: stream.read(1048576), b''):
            value.update(raw)
    return value.hexdigest()


def check_file(row):
    path = Path(row['path'])
    assert path.is_absolute() and path.resolve(strict=True) == path
    assert not path.is_symlink() and path.is_file() and path.stat().st_nlink == 1
    assert path.stat().st_size == row['bytes'] and sha_file(path) == row['sha256']
    return path


def main():
    assert os.environ.get('SLURM_JOB_ID') and os.environ.get('CUDA_VISIBLE_DEVICES') == ''
    started = time.monotonic()
    import numpy as np
    import pyproj
    import rasterio
    import shapely
    from rasterio.windows import Window
    from shapely.geometry import shape
    from shapely.geometry.polygon import orient
    raw_contract = (ROOT / 'NUMERICAL_CONTRACT.json').read_bytes()
    contract = json.loads(raw_contract)
    assert ROOT.as_posix() == contract['numerical_root'] and not (ROOT / 'SUMMARY.json').exists()
    inputs = {name: check_file(row) for name, row in contract['files'].items()}
    doc = json.loads(inputs['geometry'].read_bytes())
    assert len(doc['features']) == 12
    assert [str(f['properties']['basin_id']) for f in doc['features']] == contract['ids']
    references = {r['basin_id']: r for r in csv.DictReader(inputs['old_reference'].open())}
    geod = pyproj.Geod(ellps='WGS84')

    def measure(part):
        if part.is_empty or part.geom_type in ('Point', 'MultiPoint', 'LineString', 'MultiLineString'):
            return 0.0
        if part.geom_type == 'Polygon':
            return abs(geod.geometry_area_perimeter(orient(part, sign=1.0))[0])
        return sum(measure(g) for g in part.geoms)

    rows = []
    total_window_values = 0
    with rasterio.open(inputs['depth']) as depth, rasterio.open(inputs['mask']) as land:
        CONTEXT['original_headers'] = dict(depth_crs=str(depth.crs), mask_crs=str(land.crs),
                                         depth_nodata=repr(depth.nodata), mask_nodata=repr(land.nodata),
                                         depth_dtype=depth.dtypes, mask_dtype=land.dtypes,
                                         depth_shape=depth.shape, mask_shape=land.shape,
                                         depth_transform=list(depth.transform), mask_transform=list(land.transform))
        assert depth.crs.to_epsg() == land.crs.to_epsg() == 4326
        assert depth.transform == land.transform and depth.shape == land.shape == (18000, 43200)
        assert depth.count == land.count == 1 and depth.nodata == -1
        assert land.nodata is None or land.nodata not in (0, 1, 2, 3, 4), 'MASK_NODATA_CLASS_SEMANTIC_CONFLICT'
        transform = depth.transform
        assert transform.b == transform.d == 0 and transform.a > 0 and transform.e < 0
        assert contract['nominal_grid_coefficient_absolute_degrees'] == 1e-12
        assert all(abs(actual - expected) <= contract['nominal_grid_coefficient_absolute_degrees']
                   for actual, expected in ((transform.a, 1 / 120), (transform.e, -1 / 120),
                                            (transform.c, -180.0), (transform.f, 90.0)))
        grid = dict(crs=depth.crs.to_string(), transform=list(transform), shape=list(depth.shape),
                    depth_dtype=depth.dtypes[0], mask_dtype=land.dtypes[0], depth_nodata=depth.nodata,
                    mask_nodata=dict(type=type(land.nodata).__name__, representation=repr(land.nodata)))
        for feature in doc['features']:
            basin = str(feature['properties']['basin_id'])
            CONTEXT['basin_id'] = basin
            geom_hash = hashlib.sha256(json.dumps(feature['geometry'], sort_keys=True,
                                                  separators=(',', ':')).encode()).hexdigest()
            assert geom_hash == contract['geometry_sha256'][basin]
            geom = shape(feature['geometry'])
            assert geom.is_valid and not geom.is_empty and geom.geom_type in ('Polygon', 'MultiPolygon')
            xmin, ymin, xmax, ymax = geom.bounds
            inverse = ~transform
            upper_col, upper_row = inverse * (xmin, ymax)
            lower_col, lower_row = inverse * (xmax, ymin)
            c0, r0 = math.floor(upper_col), math.floor(upper_row)
            c1, r1 = math.ceil(lower_col), math.ceil(lower_row)
            assert 0 <= c0 < c1 <= depth.width and 0 <= r0 < r1 <= depth.height
            width = c1 - c0
            count = width * (r1 - r0)
            assert count <= contract['maximum_window_pixels'][basin] and width <= 32768
            total_window_values += count
            assert total_window_values <= contract['maximum_total_window_pixels']
            step_rows = max(1, 32768 // width)
            parts = []
            row_areas = {}
            for begin in range(r0, r1, step_rows):
                height = min(step_rows, r1 - begin)
                block = Window(c0, begin, width, height)
                values, labels = depth.read(1, window=block), land.read(1, window=block)
                assert values.shape == labels.shape == (height, width)
                rr, cc = np.indices(values.shape)
                global_rows, global_cols = (rr + begin).ravel(), (cc + c0).ravel()
                left = transform.c + global_cols * transform.a
                top = transform.f + global_rows * transform.e
                right = transform.c + (global_cols + 1) * transform.a
                bottom = transform.f + (global_rows + 1) * transform.e
                cells = shapely.box(left, bottom, right, top)
                hit = shapely.intersects(cells, geom)
                cells, source_rows, source_cols = cells[hit], global_rows[hit], global_cols[hit]
                raw_depth, raw_labels = values.ravel()[hit], labels.ravel()[hit]
                whole = shapely.covers(geom, cells)
                weights = np.empty(len(cells), dtype=np.float64)
                for row_index in np.unique(source_rows[whole]):
                    key = int(row_index)
                    if key not in row_areas:
                        latitude = transform.f + key * transform.e
                        row_areas[key] = abs(geod.polygon_area_perimeter(
                            [0, transform.a, transform.a, 0],
                            [latitude + transform.e, latitude + transform.e, latitude, latitude])[0])
                    weights[(source_rows == row_index) & whole] = row_areas[key]
                for index in np.flatnonzero(~whole):
                    weights[index] = measure(cells[index].intersection(geom))
                assert np.all(np.isfinite(weights)) and np.all(weights >= 0), 'INVALID_PIXEL_WEIGHTS'
                positive = weights > 0
                parts.append((source_rows[positive], source_cols[positive], raw_depth[positive],
                              raw_labels[positive], weights[positive]))
            arrays = [np.concatenate([part[i] for part in parts]) for i in range(5)]
            source_rows, source_cols, values, labels, weights = arrays
            geometric_area = measure(geom)
            overlap_area = float(weights.sum())
            assert geometric_area > 0 and overlap_area > 0
            area_error = abs(overlap_area / geometric_area - 1)
            assert area_error < 0.005
            nodata = values == depth.nodata
            valid_depth = np.isfinite(values) & (values >= 0) & (values <= 50)
            unknown_label = ~np.isin(labels, [0, 1, 2, 3, 4])
            invalid_depth = ~valid_depth & ~nodata
            categories = []
            for code in range(5):
                selected = labels == code
                categories.append(dict(dominant_class=code, area_m2=float(weights[selected].sum()),
                                       nodata_depth_area_m2=float(weights[selected & nodata].sum()),
                                       valid_depth_area_m2=float(weights[selected & valid_depth].sum()),
                                       valid_zero_depth_area_m2=float(weights[selected & valid_depth & (values == 0)].sum()),
                                       positive_overlap_cells=int(selected.sum())))
            valid_area = float(weights[valid_depth].sum())
            mean = float(np.dot(values[valid_depth], weights[valid_depth]) / valid_area) if valid_area else None
            unit = dict(basin_id=basin, geometry_sha256=geom_hash, original_geometry_area_m2=geometric_area,
                        grid_overlap_area_m2=overlap_area, grid_polygon_relative_area_error=area_error,
                        source_window=[c0, r0, width, r1 - r0], window_pixels_read=count,
                        positive_overlap_cells=len(values), categories=categories,
                        nodata_depth_area_m2=float(weights[nodata].sum()),
                        valid_depth_area_m2=valid_area, valid_depth_mean_m=mean,
                        valid_depth_area_fraction=valid_area / overlap_area,
                        valid_zero_depth_area_m2=float(weights[valid_depth & (values == 0)].sum()),
                        land_class_nodata_area_m2=float(weights[nodata & np.isin(labels, [1, 2])].sum()),
                        ocean_lake_ice_class_nodata_area_m2=float(weights[nodata & np.isin(labels, [0, 3, 4])].sum()),
                        unknown_class_area_m2=float(weights[unknown_label].sum()),
                        invalid_depth_area_m2=float(weights[invalid_depth].sum()),
                        original_reference_record=references[basin], input_approved=False,
                        dominant_class_is_not_subpixel_water_fraction=True, nodata_not_filled=True)
            target = ROOT / f'pixels_{basin}.npz'
            assert not target.exists()
            with target.open('xb') as stream:
                np.savez_compressed(stream, row=source_rows, col=source_cols, depth=values,
                                    dominant_class=labels, area_m2=weights)
            unit['pixel_file'] = dict(path=target.as_posix(), bytes=target.stat().st_size, sha256=sha_file(target))
            rows.append(unit)
    for name in ('geometry', 'old_reference', 'depth', 'mask'):
        assert sha_file(inputs[name]) == contract['files'][name]['sha256']
    report = dict(status='TWELVE_SOIL_NODATA_CLASSIFICATION_CANDIDATE_SAVED', job_id=os.environ['SLURM_JOB_ID'],
                  source_sha256=sha_file(__file__), contract_sha256=hashlib.sha256(raw_contract).hexdigest(),
                  grid=grid, members=rows, member_count=12, total_window_pixels_read=total_window_values,
                  source_files=contract['files'], model_calls=0, training=0, science_data_requests=0,
                  observed_station_validations=0, national_input_acceptance=False, production_accepted=0,
                  independent_numerical_review_complete=False, nodata_fill_operations=0,
                  elapsed_seconds=time.monotonic() - started,
                  peak_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    output = (json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode()
    assert len(output) <= 131072
    with (ROOT / 'SUMMARY.json').open('xb') as stream:
        stream.write(output)
    print('OWN_SOIL_MAIN_COMPLETE', flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        failure = dict(status='FAIL_SOIL_MAIN', job_id=os.environ.get('SLURM_JOB_ID'), context=CONTEXT,
                       error_type=type(error).__name__, error=str(error),
                       traceback=traceback.format_exc()[-8192:], model_calls=0, training=0,
                       national_input_acceptance=False, production_accepted=0)
        with (ROOT / 'MAIN_FAILURE.json').open('xb') as stream:
            stream.write((json.dumps(failure, indent=2, allow_nan=False) + '\n').encode())
        print('OWN_SOIL_MAIN_FAILED_REPORT_SAVED', flush=True)
        sys.exit(1)
