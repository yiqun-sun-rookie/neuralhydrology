"""Candidate: independently intersect every original target pixel on HPC."""
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import sys
import time
import traceback
import zipfile

ROOT = Path(__file__).resolve().parent
CONTEXT = {}


def checksum(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as source:
        while True:
            chunk = source.read(1048576)
            if not chunk:
                break
            result.update(chunk)
    return result.hexdigest()


def verify_file(row):
    path = Path(row['path'])
    assert path.resolve(strict=True) == path and path.is_file() and path.stat().st_nlink == 1
    assert path.stat().st_size == row['bytes'] and checksum(path) == row['sha256']
    return path


def run():
    assert os.environ.get('SLURM_JOB_ID') and os.environ.get('CUDA_VISIBLE_DEVICES') == ''
    began = time.monotonic()
    import numpy as np
    import pyproj
    import rasterio
    from rasterio.windows import Window
    from shapely.geometry import box, shape
    from shapely.geometry.polygon import orient
    entry_raw = (ROOT / 'INDEPENDENT_CONTRACT.json').read_bytes()
    entry = json.loads(entry_raw)
    assert ROOT.as_posix() == entry['independent_root'] and not (ROOT / 'INDEPENDENT_RESULT.json').exists()
    contract_path = verify_file(entry['numerical_contract'])
    main_path = verify_file(entry['main_summary'])
    contract_raw = contract_path.read_bytes()
    contract = json.loads(contract_raw)
    author = json.loads(main_path.read_bytes())
    assert author['contract_sha256'] == hashlib.sha256(contract_raw).hexdigest()
    assert author['source_sha256'] == entry['expected_main_source_sha256']
    assert author['member_count'] == 12 and [u['basin_id'] for u in author['members']] == contract['ids']
    source_paths = {key: verify_file(value) for key, value in contract['files'].items()}
    geometry = json.loads(source_paths['geometry'].read_bytes())
    assert len(geometry['features']) == 12
    reference = {unit['basin_id']: unit for unit in author['members']}
    geodesic = pyproj.Geod(ellps='WGS84')
    tolerances = entry['area_tolerances']
    errors = []
    error_count = 0
    maximum_reported_absolute_difference = 0.0
    error_path = ROOT / 'ALL_NUMERICAL_DIFFERENCES.jsonl'
    error_stream = error_path.open('xb')
    error_bytes = 0
    outcomes = []
    total_pixels_read = 0

    def overlap_area(fragment):
        kind = fragment.geom_type
        if fragment.is_empty or kind in ('Point', 'MultiPoint', 'LineString', 'MultiLineString'):
            return 0.0
        if kind == 'Polygon':
            return abs(geodesic.geometry_area_perimeter(orient(fragment, sign=1.0))[0])
        return math.fsum(overlap_area(part) for part in fragment.geoms)

    def require_close(actual, expected, label, absolute, relative):
        nonlocal error_count, maximum_reported_absolute_difference, error_bytes
        if not (math.isfinite(actual) and math.isfinite(expected)
                and abs(actual - expected) <= max(absolute, relative * max(abs(actual), abs(expected)))):
            error_count += 1
            difference = abs(actual - expected) if math.isfinite(actual) and math.isfinite(expected) else None
            if difference is not None:
                maximum_reported_absolute_difference = max(maximum_reported_absolute_difference, difference)
            row = dict(field=label, independent=actual if math.isfinite(actual) else repr(actual),
                       author=expected if math.isfinite(expected) else repr(expected), absolute_difference=difference)
            raw = (json.dumps(row, separators=(',', ':'), allow_nan=False) + '\n').encode()
            error_bytes += len(raw)
            assert error_bytes <= entry['maximum_error_evidence_bytes'], 'ERROR_EVIDENCE_BUDGET_EXCEEDED'
            error_stream.write(raw)
            if len(errors) < 100:
                errors.append(row)

    with rasterio.open(source_paths['depth']) as soil, rasterio.open(source_paths['mask']) as classes:
        assert soil.crs.to_epsg() == classes.crs.to_epsg() == 4326
        assert soil.transform == classes.transform and soil.shape == classes.shape == (18000, 43200)
        assert soil.count == classes.count == 1 and soil.nodata == -1
        assert classes.nodata is None or classes.nodata not in (0, 1, 2, 3, 4), 'MASK_NODATA_CLASS_SEMANTIC_CONFLICT'
        assert dict(type=type(classes.nodata).__name__, representation=repr(classes.nodata)) == author['grid']['mask_nodata']
        affine = soil.transform
        assert affine.b == affine.d == 0 and affine.a > 0 and affine.e < 0
        assert contract['nominal_grid_coefficient_absolute_degrees'] == 1e-12
        assert all(abs(actual - expected) <= contract['nominal_grid_coefficient_absolute_degrees']
                   for actual, expected in ((affine.a, 1 / 120), (affine.e, -1 / 120),
                                            (affine.c, -180.0), (affine.f, 90.0)))
        for feature in geometry['features']:
            basin = str(feature['properties']['basin_id'])
            CONTEXT['basin_id'] = basin
            geom_hash = hashlib.sha256(json.dumps(feature['geometry'], sort_keys=True,
                                                  separators=(',', ':')).encode()).hexdigest()
            assert geom_hash == contract['geometry_sha256'][basin]
            region = shape(feature['geometry'])
            assert region.is_valid and not region.is_empty
            old = reference[basin]
            xmin, ymin, xmax, ymax = region.bounds
            # Use the actual affine inverse for the independently indexed original window.
            inverse = ~affine
            upper_col, upper_row = inverse * (xmin, ymax)
            lower_col, lower_row = inverse * (xmax, ymin)
            column_min, row_min = math.floor(upper_col), math.floor(upper_row)
            column_max, row_max = math.ceil(lower_col), math.ceil(lower_row)
            assert 0 <= column_min < column_max <= soil.width and 0 <= row_min < row_max <= soil.height
            assert [column_min, row_min, column_max - column_min, row_max - row_min] == old['source_window']
            window_pixels = (column_max - column_min) * (row_max - row_min)
            assert window_pixels <= contract['maximum_window_pixels'][basin]
            total_pixels_read += window_pixels
            assert total_pixels_read <= contract['maximum_total_window_pixels']
            pixel_path = verify_file(old['pixel_file'])
            with zipfile.ZipFile(pixel_path) as archive:
                assert len(archive.infolist()) == 5
                assert sum(x.file_size for x in archive.infolist()) <= contract['maximum_window_pixels'][basin] * 40 + 4096
            with np.load(pixel_path, allow_pickle=False) as saved:
                arrays = {key: saved[key] for key in ('row', 'col', 'depth', 'dominant_class', 'area_m2')}
            length = len(arrays['row'])
            assert all(v.shape == (length,) for v in arrays.values()) and length == old['positive_overlap_cells']
            position = 0
            category_areas = [[] for _ in range(5)]
            category_nodata = [[] for _ in range(5)]
            category_valid = [[] for _ in range(5)]
            category_zero = [[] for _ in range(5)]
            category_counts = [0] * 5
            all_weights, valid_weights, weighted_values, nodata_weights = [], [], [], []
            invalid_weights, unknown_weights, zero_weights, land_missing, water_ice_missing = [], [], [], [], []
            maximum_pixel_difference = 0.0
            for row in range(row_min, row_max):
                width = column_max - column_min
                assert width <= 32768
                depths = soil.read(1, window=Window(column_min, row, width, 1))[0]
                labels = classes.read(1, window=Window(column_min, row, width, 1))[0]
                assert len(depths) == len(labels) == width
                for offset, column in enumerate(range(column_min, column_max)):
                    # Same original grid corner convention, independent scalar expression.
                    left, top = affine.c + column * affine.a, affine.f + row * affine.e
                    right, bottom = affine.c + (column + 1) * affine.a, affine.f + (row + 1) * affine.e
                    cell = box(left, bottom, right, top)
                    if not region.intersects(cell):
                        continue
                    weight = overlap_area(region.intersection(cell))
                    assert math.isfinite(weight) and weight >= 0, 'INVALID_INDEPENDENT_PIXEL_WEIGHT'
                    if weight <= 0:
                        continue
                    assert position < length
                    depth, label = float(depths[offset]), float(labels[offset])
                    assert int(arrays['row'][position]) == row and int(arrays['col'][position]) == column
                    assert arrays['depth'].dtype == depths.dtype and arrays['dominant_class'].dtype == labels.dtype
                    assert arrays['depth'][position].tobytes() == depths[offset].tobytes()
                    assert arrays['dominant_class'][position].tobytes() == labels[offset].tobytes()
                    author_weight = float(arrays['area_m2'][position])
                    maximum_pixel_difference = max(maximum_pixel_difference, abs(weight - author_weight))
                    require_close(weight, author_weight, basin + '/pixel/' + str(position),
                                  tolerances['cell_absolute_m2'], tolerances['cell_relative'])
                    position += 1
                    all_weights.append(weight)
                    nodata = depth == -1
                    valid = math.isfinite(depth) and 0 <= depth <= 50
                    if nodata:
                        nodata_weights.append(weight)
                        if label in (1, 2):
                            land_missing.append(weight)
                        if label in (0, 3, 4):
                            water_ice_missing.append(weight)
                    if valid:
                        valid_weights.append(weight)
                        weighted_values.append(weight * depth)
                        if depth == 0:
                            zero_weights.append(weight)
                    elif not nodata:
                        invalid_weights.append(weight)
                    if label in (0, 1, 2, 3, 4):
                        code = int(label)
                        category_counts[code] += 1
                        category_areas[code].append(weight)
                        if nodata:
                            category_nodata[code].append(weight)
                        if valid:
                            category_valid[code].append(weight)
                            if depth == 0:
                                category_zero[code].append(weight)
                    else:
                        unknown_weights.append(weight)
            assert position == length
            original_area = overlap_area(region)
            result = dict(basin_id=basin, original_geometry_area_m2=original_area,
                          grid_overlap_area_m2=math.fsum(all_weights), valid_depth_area_m2=math.fsum(valid_weights),
                          nodata_depth_area_m2=math.fsum(nodata_weights),
                          valid_zero_depth_area_m2=math.fsum(zero_weights),
                          land_class_nodata_area_m2=math.fsum(land_missing),
                          ocean_lake_ice_class_nodata_area_m2=math.fsum(water_ice_missing),
                          invalid_depth_area_m2=math.fsum(invalid_weights), unknown_class_area_m2=math.fsum(unknown_weights),
                          positive_overlap_cells=position, window_pixels_read=window_pixels,
                          maximum_pixel_area_difference_m2=maximum_pixel_difference, categories=[])
            result['valid_depth_mean_m'] = (math.fsum(weighted_values) / result['valid_depth_area_m2']
                                            if result['valid_depth_area_m2'] else None)
            result['valid_depth_area_fraction'] = result['valid_depth_area_m2'] / result['grid_overlap_area_m2']
            result['grid_polygon_relative_area_error'] = abs(result['grid_overlap_area_m2'] / original_area - 1)
            assert result['grid_polygon_relative_area_error'] < 0.005
            assert result['window_pixels_read'] == old['window_pixels_read']
            for key in ('valid_depth_area_fraction', 'grid_polygon_relative_area_error'):
                require_close(result[key], old[key], basin + '/' + key,
                              entry['fraction_absolute'], entry['fraction_relative'])
            for key in ('original_geometry_area_m2', 'grid_overlap_area_m2', 'valid_depth_area_m2',
                        'nodata_depth_area_m2', 'valid_zero_depth_area_m2', 'land_class_nodata_area_m2',
                        'ocean_lake_ice_class_nodata_area_m2', 'invalid_depth_area_m2', 'unknown_class_area_m2'):
                require_close(result[key], old[key], basin + '/' + key,
                              tolerances['unit_absolute_m2'], tolerances['unit_relative'])
            if result['valid_depth_mean_m'] is None:
                assert old['valid_depth_mean_m'] is None
            else:
                require_close(result['valid_depth_mean_m'], old['valid_depth_mean_m'], basin + '/mean',
                              entry['mean_depth_absolute_m'], entry['mean_depth_relative'])
            for code in range(5):
                row = dict(dominant_class=code, area_m2=math.fsum(category_areas[code]),
                           nodata_depth_area_m2=math.fsum(category_nodata[code]),
                           valid_depth_area_m2=math.fsum(category_valid[code]),
                           valid_zero_depth_area_m2=math.fsum(category_zero[code]),
                           positive_overlap_cells=category_counts[code])
                assert row['positive_overlap_cells'] == old['categories'][code]['positive_overlap_cells']
                for key in ('area_m2', 'nodata_depth_area_m2', 'valid_depth_area_m2', 'valid_zero_depth_area_m2'):
                    require_close(row[key], old['categories'][code][key], basin + '/class' + str(code) + '/' + key,
                                  tolerances['unit_absolute_m2'], tolerances['unit_relative'])
                result['categories'].append(row)
            outcomes.append(result)
    for name, path in source_paths.items():
        assert checksum(path) == contract['files'][name]['sha256']
    assert checksum(contract_path) == entry['numerical_contract']['sha256']
    assert checksum(main_path) == entry['main_summary']['sha256']
    for unit in author['members']:
        verify_file(unit['pixel_file'])
    error_stream.close()
    report = dict(status='PASS_INDEPENDENT_CLASSIFICATION_RECONSTRUCTION' if not error_count else 'FAIL_INDEPENDENT_COMPARISON',
                  job_id=os.environ['SLURM_JOB_ID'], source_sha256=checksum(__file__),
                  contract_sha256=hashlib.sha256(entry_raw).hexdigest(), original_sources=contract['files'],
                  independent_original_pixel_reconstruction=True, main_summary=entry['main_summary'],
                  member_count=12, members=outcomes, first_errors=errors, error_count=error_count,
                  all_differences=dict(path=error_path.as_posix(), bytes=error_bytes, sha256=checksum(error_path)),
                  maximum_reported_absolute_difference=maximum_reported_absolute_difference,
                  original_window_pixels_read=total_pixels_read, model_calls=0, training=0,
                  scientific_requests=0, observed_station_validations=0, national_input_acceptance=False,
                  production_accepted=0, nodata_fill_operations=0, frozen_tolerances=tolerances,
                  elapsed_seconds=time.monotonic() - began, peak_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    output = (json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode()
    assert len(output) <= 131072
    with (ROOT / 'INDEPENDENT_RESULT.json').open('xb') as stream:
        stream.write(output)
    print('OWN_SOIL_INDEPENDENT_COMPLETE', flush=True)
    return 0 if error_count == 0 else 1


if __name__ == '__main__':
    try:
        sys.exit(run())
    except Exception as error:
        failure = dict(status='FAIL_INDEPENDENT_EXECUTION', job_id=os.environ.get('SLURM_JOB_ID'), context=CONTEXT,
                       error_type=type(error).__name__, error=str(error),
                       traceback=traceback.format_exc()[-8192:], model_calls=0, training=0,
                       national_input_acceptance=False, production_accepted=0)
        with (ROOT / 'INDEPENDENT_FAILURE.json').open('xb') as stream:
            stream.write((json.dumps(failure, indent=2, allow_nan=False) + '\n').encode())
        print('OWN_SOIL_INDEPENDENT_FAILED_REPORT_SAVED', flush=True)
        sys.exit(1)
