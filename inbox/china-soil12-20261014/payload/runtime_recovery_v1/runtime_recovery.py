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
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener
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


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError('WHEEL_REDIRECT_FORBIDDEN')


def wheel_child(filename):
    assert os.environ.get('SLURM_JOB_ID') and os.environ.get('CUDA_VISIBLE_DEVICES') == ''
    contract = json.loads((ROOT / 'RUNTIME_RECOVERY_CONTRACT.json').read_bytes())
    assert filename in contract['wheels'] and Path(filename).name == filename
    directory = ROOT / 'wheel_bytes_v1'
    assert directory.is_dir()
    marker = directory / (filename + '.started.json')
    save(marker, dict(single_get=True, automatic_retries=0))
    source = contract['wheels'][filename]
    row = dict(filename=filename, status='HELD', bytes_expected=source['bytes'],
               sha256_expected=source['sha256'], source_url=source['url'], actual_bytes=0,
               scientific_tiff_gets=0, authentication_used=False, automatic_retries=0)
    digest = hashlib.sha256()
    try:
        assert source['url'].startswith('https://files.pythonhosted.org/packages/')
        with (directory / filename).open('xb') as stream:
            with build_opener(NoRedirect()).open(Request(source['url']), timeout=120) as response:
                row.update(http_status=response.status, content_length=response.headers.get('Content-Length'))
                assert response.status == 200
                assert row['content_length'] is None or int(row['content_length']) == source['bytes']
                while True:
                    data = response.read1(min(1048576, source['bytes'] + 1 - row['actual_bytes']))
                    if not data:
                        break
                    row['actual_bytes'] += len(data)
                    stream.write(data)
                    stream.flush()
                    digest.update(data)
                    assert row['actual_bytes'] <= source['bytes']
        row['actual_sha256'] = digest.hexdigest()
        assert row['actual_bytes'] == source['bytes'] and row['actual_sha256'] == source['sha256']
        row['status'] = 'VERIFIED_ORIGINAL_WHEEL_BYTES'
    except HTTPError as error:
        row.update(http_status=error.code, error_type='HTTPError')
    except URLError as error:
        row.update(error_type='URLError', underlying_connection_error_type=type(error.reason).__name__)
    except Exception as error:
        row['error_type'] = type(error).__name__
    print(json.dumps(row))


def main():
    assert os.environ.get('SLURM_JOB_ID') and os.environ.get('CUDA_VISIBLE_DEVICES') == ''
    started = time.monotonic()
    report = dict(status='HELD', job_id=os.environ['SLURM_JOB_ID'], host=socket.gethostname(),
                  python_version=sys.version, architecture=platform.machine(), libc=platform.libc_ver(),
                  array_reads=0, scientific_tiff_gets=0, wheel_get_attempts=0, model_calls=0, training=0,
                  shared_environment_changes=0, national_input_acceptance=False, production_accepted=0,
                  packages=[], wheel_acquisition=[], geometry_records=[])
    try:
        raw_contract = (ROOT / 'RUNTIME_RECOVERY_CONTRACT.json').read_bytes()
        contract = json.loads(raw_contract)
        assert ROOT.as_posix() == contract['remote_root']
        report['contract_sha256'] = sha(raw_contract)
        report['source_sha256'] = sha(Path(__file__).read_bytes())
        assert sys.version_info[:2] == (3, 11) and platform.machine() == 'x86_64'
        for name, row in contract['inputs'].items():
            file_check(ROOT / name, row)
        assert len(contract['wheels']) == 10 and sum(r['bytes'] for r in contract['wheels'].values()) == 34359672
        directory = ROOT / 'wheel_bytes_v1'
        assert not directory.exists()
        directory.mkdir()
        download_started = time.monotonic()
        zipped = {}
        for filename, source in contract['wheels'].items():
            remaining = 600 - (time.monotonic() - download_started)
            assert remaining > 0
            budget = min(120, remaining)
            request_started = time.monotonic()
            report['wheel_get_attempts'] += 1
            try:
                completed = subprocess.run([sys.executable, '-B', '-u', str(Path(__file__).resolve()),
                                            'wheel_child', filename], stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, timeout=budget)
                assert completed.returncode == 0 and not completed.stderr and len(completed.stdout) <= 8192
                row = json.loads(completed.stdout)
                assert time.monotonic() - request_started <= budget
            except subprocess.TimeoutExpired:
                row = dict(filename=filename, status='HELD_WALL_CLOCK_LIMIT',
                           error_type='KilledOwnAcquisitionSubprocess')
            except Exception as error:
                row = dict(filename=filename, status='HELD', error_type=type(error).__name__)
            candidate = directory / filename
            row.update(parent_wall_seconds=time.monotonic() - request_started, wall_clock_limit_seconds=budget,
                       preserved_candidate_bytes=candidate.stat().st_size if candidate.exists() else 0)
            save(directory / (filename + '.result.json'), row)
            report['wheel_acquisition'].append(row)
            assert row['status'] == 'VERIFIED_ORIGINAL_WHEEL_BYTES', 'PRIVATE_WHEEL_ACQUISITION_HELD'
            file_check(candidate, source)
            zipped[filename] = candidate.read_bytes()
        assert time.monotonic() - download_started < 600
        target = ROOT.parent / 'deps_v1'
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
    save(ROOT / 'RUNTIME_RECOVERY_RESULT.json', report)
    print('OWN_RUNTIME_RECOVERY_REPORT_SAVED')
    print('OWN_RUNTIME_RECOVERY_STATUS=' + report['status'])
    return 0 if report['status'] == 'PASS_PRIVATE_RUNTIME_AND_PROVISIONAL_WINDOWS' else 1


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'wheel_child':
        wheel_child(sys.argv[2])
    else:
        assert len(sys.argv) == 1
        sys.exit(main())
