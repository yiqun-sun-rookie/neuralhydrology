#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 110s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'ALTERNATIVE_DOCUMENT'
"""HPC-only retrieval of one exact public data dictionary, never the science ZIP."""
import base64
import datetime
import hashlib
import json
import resource
import signal
import time
from urllib.error import HTTPError
from urllib.parse import urljoin, urlparse
from urllib.request import build_opener, HTTPRedirectHandler, ProxyHandler, Request

START = time.monotonic()


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def expired(*_):
    raise TimeoutError('Bounded original documentation deadline')


def allowed(url):
    u = urlparse(url)
    host = u.hostname or ''
    assert u.scheme == 'https' and u.port in (None, 443) and u.username is None and u.password is None and not u.fragment
    assert host == 'borealisdata.ca' or host.endswith('.scholarsportal.info') or host.endswith('.amazonaws.com')


def main():
    resource.setrlimit(resource.RLIMIT_AS, (256 * 1024**2, resource.getrlimit(resource.RLIMIT_AS)[1]))
    signal.signal(signal.SIGALRM, expired)
    opener = build_opener(ProxyHandler({}), NoRedirect())
    result = dict(kind='GAP27888_ALTERNATIVE_DOCUMENT', complete=False, doi='doi:10.5683/SP2/TTJNIU',
                  file_id=71773, filename='Readme_GLHYMPS2_0.txt', expected_bytes=4375,
                  expected_md5='848d528b91485faa74f4b03566338cae', responses=[], document=None,
                  new_jobs=0, source_content_reads=0, source_decoding=0, source_writes=0,
                  scientific_archives_downloaded=0, model_calls=0, automatic_checks_enabled=False,
                  scientific_input_accepted=False, prediction_approved=False)
    url = 'https://borealisdata.ca/api/access/datafile/71773'
    for hop in range(3):
        allowed(url)
        remaining = 100 - (time.monotonic() - START)
        assert remaining > 0
        signal.setitimer(signal.ITIMER_REAL, min(30, remaining))
        began = time.monotonic()
        row = dict(host=urlparse(url).hostname, path=urlparse(url).path,
                   url_sha256=hashlib.sha256(url.encode()).hexdigest(), status=None)
        result['responses'].append(row)
        response = None
        redirect = None
        try:
            request = Request(url, headers={'User-Agent': 'china-gap27888-document/1', 'Accept-Encoding': 'identity'})
            try:
                response = opener.open(request, timeout=min(30, remaining))
            except HTTPError as error:
                response = error
            row.update(status=response.code, declared_length=response.headers.get('Content-Length'),
                       content_type=response.headers.get('Content-Type'))
            assert response.headers.get('Content-Encoding', 'identity') == 'identity'
            raw = response.read(65537)
            row.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), base64=base64.b64encode(raw).decode())
            assert len(raw) <= 65536
            assert row['declared_length'] is None or int(row['declared_length']) == len(raw)
            if response.code in (301, 302, 303, 307, 308):
                redirect = urljoin(url, response.headers['Location'])
                allowed(redirect)
                row['redirect_host'] = urlparse(redirect).hostname
                row['redirect_url_sha256'] = hashlib.sha256(redirect.encode()).hexdigest()
            else:
                assert response.code == 200 and len(raw) == 4375
                assert hashlib.md5(raw).hexdigest() == result['expected_md5']
                result['document'] = dict(bytes=len(raw), md5=hashlib.md5(raw).hexdigest(),
                                          sha256=hashlib.sha256(raw).hexdigest(), base64=base64.b64encode(raw).decode())
                result['complete'] = True
        except MemoryError:
            raise
        except Exception as error:
            row['error'] = dict(type=type(error).__name__, message=str(error)[:500])
            redirect = None
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            if response is not None:
                response.close()
            row['seconds'] = time.monotonic() - began
            if row['seconds'] >= 30:
                result['complete'] = False
                result['document'] = None
                redirect = None
                row['time_gate_failed'] = True
        if redirect is None:
            break
        url = redirect
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

ALTERNATIVE_DOCUMENT
