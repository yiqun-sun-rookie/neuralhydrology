#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 110s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'ALTERNATIVE_CATALOGUE'
"""Two bounded public catalogue reads on HPC; no scientific file downloads."""
import base64
import datetime
import hashlib
import json
import resource
import signal
import time
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import build_opener, HTTPRedirectHandler, ProxyHandler, Request

START = time.monotonic()
DOI = 'doi:10.5683/SP2/TTJNIU'
URLS = [
    'https://borealisdata.ca/api/datasets/:persistentId/?persistentId=doi%3A10.5683%2FSP2%2FTTJNIU',
    'https://borealisdata.ca/api/datasets/export?exporter=dataverse_json&persistentId=doi%3A10.5683%2FSP2%2FTTJNIU',
]


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def expired(*_):
    raise TimeoutError('Bounded public catalogue deadline')


def main():
    resource.setrlimit(resource.RLIMIT_AS, (256 * 1024**2, resource.getrlimit(resource.RLIMIT_AS)[1]))
    signal.signal(signal.SIGALRM, expired)
    opener = build_opener(ProxyHandler({}), NoRedirect())
    result = dict(kind='GAP27888_ALTERNATIVE_CATALOGUE', member='27888', doi=DOI,
                  complete=False, responses=[], catalogue=None, new_jobs=0, source_content_reads=0,
                  source_decoding=0, source_writes=0, scientific_archives_downloaded=0, model_calls=0,
                  automatic_checks_enabled=False, scientific_input_accepted=False, prediction_approved=False)
    for index, url in enumerate(URLS):
        remaining = 100 - (time.monotonic() - START)
        if remaining <= 0:
            result['error'] = 'GLOBAL_DEADLINE'
            break
        assert urlparse(url).hostname == 'borealisdata.ca'
        signal.setitimer(signal.ITIMER_REAL, min(45, remaining))
        began = time.monotonic()
        row = dict(url=url, status=None, accepted=False)
        result['responses'].append(row)
        response = None
        try:
            request = Request(url, headers={'User-Agent': 'china-gap27888-catalogue/1', 'Accept-Encoding': 'identity'})
            try:
                response = opener.open(request, timeout=min(45, remaining))
            except HTTPError as error:
                response = error
            row['status'] = response.code
            row['content_type'] = response.headers.get('Content-Type')
            row['declared_length'] = response.headers.get('Content-Length')
            assert response.headers.get('Content-Encoding', 'identity') == 'identity'
            raw = response.read(262145)
            row.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), base64=base64.b64encode(raw).decode())
            assert len(raw) <= 262144 and row['status'] == 200
            assert row['declared_length'] is None or int(row['declared_length']) == len(raw)
            value = json.loads(raw)
            data = value['data'] if value.get('status') == 'OK' else value
            version = data.get('latestVersion') or data.get('datasetVersion')
            assert isinstance(version, dict) and version['datasetPersistentId'] == DOI
            assert version['versionState'] == 'RELEASED'
            files = []
            for item in version['files']:
                f = item['dataFile']
                files.append(dict(id=f['id'], filename=f['filename'], bytes=f['filesize'],
                                  checksum=f.get('checksum'), restricted=item.get('restricted'),
                                  description=item.get('description'), content_type=f.get('contentType')))
            assert len(files) <= 1000
            result['catalogue'] = dict(doi=DOI, version=[version['versionNumber'], version['versionMinorNumber']],
                                      release_time=version.get('releaseTime'), license=version.get('license'),
                                      metadata_blocks=version.get('metadataBlocks'), files=files,
                                      original_processing_compatibility='UNKNOWN', member_coverage='UNKNOWN')
            row['accepted'] = True
            result['complete'] = True
        except MemoryError:
            raise
        except Exception as error:
            row['error'] = dict(type=type(error).__name__, message=str(error)[:500])
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            if response is not None:
                response.close()
            row['seconds'] = time.monotonic() - began
            if row['seconds'] >= 45:
                row['accepted'] = False
                result['complete'] = False
                result['catalogue'] = None
                row['time_gate_failed'] = True
        if result['complete']:
            break
    result.update(server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), seconds=time.monotonic() - START)
    assert result['seconds'] < 100
    return result


if __name__ == '__main__':
    import zlib
    raw = (json.dumps(main(), ensure_ascii=False, allow_nan=False, separators=(',', ':')) + '\n').encode()
    assert len(raw) <= 2097152
    print('GEOLOGY_RECOVERY_BYTES=' + str(len(raw)))
    print('GEOLOGY_RECOVERY_SHA256=' + hashlib.sha256(raw).hexdigest())
    print('GEOLOGY_RECOVERY_ZLIB_BASE64=' + base64.b64encode(zlib.compress(raw)).decode())
    print('GEOLOGY_RECOVERY_DONE')

ALTERNATIVE_CATALOGUE
