"""Private binary dependency recovery and missing-sample geometry on HPC."""
import base64
import csv
import hashlib
import importlib
import importlib.metadata
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import platform
import resource
import socket
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parent


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def save(path, obj):
    raw = (json.dumps(obj, indent=2) + '\n').encode()
    assert len(raw) <= 131072
    with path.open('xb') as stream:
        stream.write(raw)


def file_check(path, row):
    assert path.resolve(strict=True) == path and path.is_file() and not path.is_symlink()
    assert path.stat().st_size == row['bytes'] and sha(path.read_bytes()) == row['sha256']


def main():
    assert os.environ.get('SLURM_JOB_ID') and os.environ.get('CUDA_VISIBLE_DEVICES') == ''
    started = time.monotonic()
    report = dict(status='HELD', job_id=os.environ['SLURM_JOB_ID'], host=socket.gethostname(),
                  python_version=sys.version, architecture=platform.machine(), libc=platform.libc_ver(),
                  array_reads=0, scientific_tiff_gets=0, wheel_get_attempts=0, model_calls=0, training=0,
                  shared_environment_changes=0, national_input_acceptance=False, production_accepted=0,
                  packages=[], wheel_acquisition=[], geometry_records=[])
    try:
        raw_contract = (ROOT / 'RUNTIME_INSTALL_CONTRACT.json').read_bytes()
        contract = json.loads(raw_contract)
        assert ROOT.as_posix() == contract['remote_root']
        report['contract_sha256'] = sha(raw_contract)
        report['source_sha256'] = sha(Path(__file__).read_bytes())
        assert sys.version_info[:2] == (3, 11) and platform.machine() == 'x86_64'
        for name, row in contract['inputs'].items():
            file_check(ROOT / name, row)
        assert len(contract['wheels']) == 10 and sum(r['bytes'] for r in contract['wheels'].values()) == 34359672
        archive = ROOT / 'WHEEL_ORIGINAL_BYTES.zip'
        file_check(archive, contract['wheel_archive'])
        zipped = {}
        with zipfile.ZipFile(archive) as bundle:
            entries = bundle.infolist()
            assert len(entries) == 10 and {x.filename for x in entries} == set(contract['wheels'])
            assert sum(x.file_size for x in entries) == 34359672 and bundle.testzip() is None
            for item in entries:
                assert Path(item.filename).name == item.filename and item.file_size <= 23000000
                source = contract['wheels'][item.filename]
                raw = bundle.read(item)
                assert len(raw) == source['bytes'] and sha(raw) == source['sha256']
                zipped[item.filename] = raw
                report['wheel_acquisition'].append(dict(filename=item.filename,
                    status='VERIFIED_ORIGINAL_WHEEL_BYTES', actual_bytes=len(raw), actual_sha256=sha(raw), network_gets=0))
        target = ROOT.parent / 'deps_v2'
        assert not target.exists()
        target.mkdir()
        total_expanded, written = 0, set()
        for filename, raw in zipped.items():
            with zipfile.ZipFile(io.BytesIO(raw)) as wheel:
                entries = wheel.infolist()
                assert len(entries) <= 10000
                assert wheel.testzip() is None
                record_names = [x.filename for x in entries if x.filename.endswith('.dist-info/RECORD')]
                assert len(record_names) == 1
                records = {r[0]: r[1:] for r in csv.reader(wheel.read(record_names[0]).decode().splitlines())}
                for item in entries:
                    name = PurePosixPath(item.filename)
                    assert not name.is_absolute() and '..' not in name.parts and '\\' not in item.filename
                    assert not (item.external_attr >> 16) & 0o170000 == 0o120000
                    assert name.suffix != '.pth' and '.data' not in name.parts
                    assert item.file_size <= 67108864
                    if item.is_dir():
                        continue
                    assert item.filename not in written and item.filename in records
                    data = wheel.read(item)
                    assert len(data) == item.file_size
                    record_hash, record_size = records[item.filename]
                    if item.filename != record_names[0]:
                        assert record_hash.startswith('sha256=') and int(record_size) == len(data)
                        digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b'=').decode()
                        assert record_hash == 'sha256=' + digest
                    total_expanded += len(data)
                    assert total_expanded <= 268435456
                    path = target.joinpath(*name.parts)
                    assert path.resolve().is_relative_to(target)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with path.open('xb') as stream:
                        stream.write(data)
                    written.add(item.filename)
        sys.path.insert(0, str(target))
        for name, version in contract['versions'].items():
            module = importlib.import_module(name)
            actual_version = importlib.metadata.version(contract['distributions'][name])
            module_path = Path(module.__file__).resolve()
            assert actual_version == version
            if name == 'numpy':
                assert not module_path.is_relative_to(target)
            else:
                assert module_path.is_relative_to(target)
            report['packages'].append(dict(module=name, version=actual_version, loaded_path=str(module_path)))
        import shapely
        from shapely.geometry import shape
        geometry = json.loads((ROOT / 'B_MISSING_SAMPLE_GEOMETRY_BYTES.geojson').read_bytes())
        report['original_crs_metadata'] = geometry.get('crs')
        assert geometry.get('crs', {}).get('properties', {}).get('name') in (
            'urn:ogc:def:crs:OGC:1.3:CRS84', 'EPSG:4326', 'urn:ogc:def:crs:EPSG::4326')
        assert len(geometry['features']) == 12
        assert [str(f['properties']['basin_id']) for f in geometry['features']] == contract['ids']
        total = 0
        for feature in geometry['features']:
            name = str(feature['properties']['basin_id'])
            geom = shape(feature['geometry'])
            assert geom.is_valid and not geom.is_empty and geom.geom_type in ('Polygon', 'MultiPolygon')
            bounds = geom.bounds
            assert all(math.isfinite(x) for x in bounds) and -180 <= bounds[0] < bounds[2] <= 180
            assert -60 <= bounds[1] < bounds[3] <= 90
            c0, c1 = math.floor((bounds[0] + 180) * 120), math.ceil((bounds[2] + 180) * 120)
            r0, r1 = math.floor((90 - bounds[3]) * 120), math.ceil((90 - bounds[1]) * 120)
            assert 0 <= c0 < c1 <= 43200 and 0 <= r0 < r1 <= 18000
            count = (c1 - c0) * (r1 - r0)
            assert count <= 1000000
            total += count
            assert total <= 6000000
            report['geometry_records'].append(dict(
                basin_id=name, bounds=list(bounds), geometry_valid=True,
                geometry_sha256=sha(json.dumps(feature['geometry'], sort_keys=True,
                                               separators=(',', ':')).encode()),
                provisional_window=[r0, r1, c0, c1], provisional_window_pixels=count,
                raster_header_not_yet_verified=True))
        report.update(status='PASS_PRIVATE_RUNTIME_AND_PROVISIONAL_WINDOWS',
                      private_dependency_uncompressed_bytes=total_expanded,
                      private_dependency_files=len(written), provisional_total_window_pixels=total)
    except Exception as error:
        report.update(error_type=type(error).__name__, error=str(error)[:2000])
    report.update(elapsed_seconds=time.monotonic() - started,
                  peak_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    save(ROOT / 'RUNTIME_INSTALL_RESULT.json', report)
    print('OWN_RUNTIME_INSTALL_REPORT_SAVED')
    print('OWN_RUNTIME_INSTALL_STATUS=' + report['status'])
    return 0 if report['status'] == 'PASS_PRIVATE_RUNTIME_AND_PROVISIONAL_WINDOWS' else 1


if __name__ == '__main__':
    assert len(sys.argv) == 1
    sys.exit(main())
