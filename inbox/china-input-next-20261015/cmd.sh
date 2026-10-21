#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 100s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'LIAONING_CATALOGUE'
"""One HPC public library catalogue; no scientific data/GIS/model execution."""
import base64
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import resource
import signal
import time
from urllib.error import HTTPError
from urllib.request import build_opener, HTTPRedirectHandler, ProxyHandler, Request
import zlib

START = time.monotonic()
ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/gap27888_liaoning_catalogue_20261021_v1')
URL = 'https://www.cgs.gov.cn/zcwj/202009/W020200903520912085599.xls'
LIMIT = 2 * 1024**2
resource.setrlimit(resource.RLIMIT_AS, (512*1024**2, 512*1024**2))


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def expired(signum, frame):
    raise TimeoutError('Frozen catalogue request deadline')


def dump(path, raw):
    with path.open('xb') as stream:
        stream.write(raw)
        stream.flush()


def main():
    ROOT.mkdir(exist_ok=False)
    result = dict(kind='GAP27888_LIAONING_CATALOGUE', member='27888', complete=False,
        metadata_session_finished=False, new_jobs=0, source_content_reads=0, source_decoding=0,
        source_writes=0, scientific_archives_downloaded=0, model_calls=0,
        automatic_checks_enabled=False, scientific_input_accepted=False, prediction_approved=False,
        permeability_units_verified=False, porosity_units_verified=False,
        member_coverage='UNKNOWN_NOT_SPATIALLY_COMPUTED', catalogue_acquired=False,
        catalogue_parsed=False, requests=1, url=URL, root=str(ROOT), response={}, matches=[])
    raw = b''
    signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, 20)
    try:
        opener = build_opener(ProxyHandler({}), NoRedirect())
        request = Request(URL, headers={'User-Agent':'HydrologySourceAudit/1.0', 'Accept-Encoding':'identity'})
        try:
            response = opener.open(request, timeout=20)
        except HTTPError as error:
            response = error
        with response:
            info = result['response']
            info.update(status=response.code, headers=list(response.headers.items()), final_url=response.geturl())
            assert response.geturl() == URL, 'No redirected endpoint'
            declared = response.headers.get('Content-Length')
            assert declared is not None and re.fullmatch(r'[0-9]+', declared), 'Required exact Content-Length'
            size = int(declared)
            info['declared_bytes'] = size
            assert 0 < size <= LIMIT, 'Catalogue byte ceiling'
            assert response.headers.get('Content-Encoding','identity').lower() in ('identity',''), 'Identity encoding required'
            while len(raw) <= size:
                piece = response.read(min(65536,size+1-len(raw)))
                if not piece:
                    break
                raw += piece
            assert len(raw) == size, 'Exact complete response length'
            info['body_complete'] = True
    except Exception as error:
        result['response']['error'] = dict(type=type(error).__name__, message=str(error)[:700])
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    result['request_seconds'] = time.monotonic()-START
    if result['request_seconds'] >= 20:
        result['response'].update(body_complete=False, time_gate_failed=True)
        result['response'].setdefault('error', dict(type='TimeoutError', message='Actual request duration exceeded 20 seconds'))
    result['response'].update(body_bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    result['response']['base64'] = base64.b64encode(raw).decode()
    dump(ROOT/'CATALOGUE_RESPONSE.bin', raw)
    result['response']['saved_path'] = str(ROOT/'CATALOGUE_RESPONSE.bin')
    if result['response'].get('status') == 200 and result['response'].get('body_complete') and raw[:8] == bytes.fromhex('d0cf11e0a1b11ae1'):
        result['catalogue_acquired'] = True
        try:
            assert importlib.util.find_spec('xlrd') is not None, 'Existing xlrd unavailable; no installation or repeat download'
            import xlrd
            result['xlrd_version'] = xlrd.__version__
            book = xlrd.open_workbook(file_contents=raw, on_demand=True)
            assert book.nsheets <= 32, 'Sheet ceiling'
            result['sheets'] = []
            pattern = re.compile(r'辽宁|锦州|锦县|锦西|凌海|盘锦|营口|大凌河|小凌河|下辽河|兴城|葫芦岛')
            total_matches = 0
            for sheet_index in range(book.nsheets):
                assert time.monotonic()-START < 80, 'Catalogue parsing time ceiling'
                sheet = book.sheet_by_index(sheet_index)
                assert sheet.nrows <= 30000 and sheet.ncols <= 128, 'Catalogue shape ceiling'
                headers = []
                for row_index in range(sheet.nrows):
                    assert time.monotonic()-START < 80, 'Catalogue parsing time ceiling'
                    cells = [str(sheet.cell_value(row_index, col_index)) for col_index in range(min(sheet.ncols,64))]
                    if row_index < 2:
                        headers.append([cell[:120] for cell in cells[:16]])
                    if pattern.search(' | '.join(cells)):
                        total_matches += 1
                        if len(result['matches']) < 120:
                            result['matches'].append(dict(sheet=sheet.name, row_1_based=row_index+1,
                                cells=[cell[:120] for cell in cells[:16]],
                                columns_omitted=max(0,sheet.ncols-16),
                                any_saved_cell_truncated=any(len(cell)>120 for cell in cells[:16])))
                result['sheets'].append(dict(name=sheet.name, rows=sheet.nrows, columns=sheet.ncols,
                    searched_columns=min(sheet.ncols,64), first_two_rows=headers))
                book.unload_sheet(sheet_index)
            book.release_resources()
            result.update(catalogue_parsed=True, total_matching_rows=total_matches,
                matching_rows_omitted=max(0,total_matches-len(result['matches'])),
                catalogue_matches_are_not_spatial_coverage=True)
        except Exception as error:
            result['parse_error'] = dict(type=type(error).__name__, message=str(error)[:700])
    elif result['response'].get('status') == 200 and result['response'].get('body_complete'):
        result['signature_error'] = 'Expected OLE2 XLS signature not present; not parsed'
    result.update(metadata_session_finished=True, complete=result['catalogue_parsed'],
        received_body_bytes=len(raw), server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        seconds=time.monotonic()-START)
    return result


if __name__ == '__main__':
    value = main()
    body = (json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',',':'))+'\n').encode()
    assert len(body) <= 4*1024**2 and time.monotonic()-START < 90, 'Final payload/time ceiling'
    dump(ROOT/'METADATA.json', body)
    encoded = base64.b64encode(zlib.compress(body)).decode()
    assert time.monotonic()-START < 90
    print('GEOLOGY_RECOVERY_BYTES='+str(len(body)))
    print('GEOLOGY_RECOVERY_SHA256='+hashlib.sha256(body).hexdigest())
    print('GEOLOGY_RECOVERY_ZLIB_BASE64='+encoded)
    print('GEOLOGY_RECOVERY_DONE', flush=True)
    assert time.monotonic()-START < 90, 'Final output/flush deadline exceeded'

LIAONING_CATALOGUE
