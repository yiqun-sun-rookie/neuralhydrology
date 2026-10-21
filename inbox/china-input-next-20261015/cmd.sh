#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 110s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GLHYMPS2_DNS_ROUTE'
"""HPC login metadata only: finite HEAD route, no scientific response body."""
import base64
import datetime
import hashlib
import http.client
import ipaddress
import json
import signal
import socket
import ssl
import time
from urllib.parse import urljoin, urlparse
import zlib

START = time.monotonic()
http.client._MAXHEADERS = 64
http.client._MAXLINE = 8192
RESULT = dict(kind='GLHYMPS2_DNS_ROUTE', complete=False, requests=[], dns=[],
              official_file_id=71909, expected_bytes=2595563951,
              scientific_HTTP_body_bytes=0, scientific_archives_downloaded=0,
              source_content_reads=0, source_decoding=0, source_writes=0,
              new_jobs=0, model_calls=0, automatic_checks_enabled=False,
              scientific_input_accepted=False, prediction_approved=False,
              operational_DNS_changed=False, TTL='UNKNOWN', DNSSEC_proof_claimed=False)


def expired(*_):
    raise TimeoutError('Finite HEAD and DNS metadata deadline')


def allowed(url):
    u = urlparse(url)
    host = u.hostname or ''
    assert u.scheme == 'https' and u.port in (None, 443) and not u.username and not u.password and not u.fragment
    assert host == 'borealisdata.ca' or host.endswith('.scholarsportal.info') or host.endswith('.amazonaws.com')
    assert len(url) <= 8192
    return u, host


def main():
    signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, 100)
    context = ssl.create_default_context()
    assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
    pins = {}
    url = 'https://borealisdata.ca/api/access/datafile/71909'
    for hop in range(3):
        u, host = allowed(url)
        row = dict(host=host, path=u.path, method='HEAD',
                   url_sha256=hashlib.sha256(url.encode()).hexdigest(), status=None)
        RESULT['requests'].append(row)
        if host not in pins:
            addresses = sorted({x[4][0] for x in socket.getaddrinfo(host, 443, socket.AF_INET, socket.SOCK_STREAM)},
                               key=lambda s: int(ipaddress.ip_address(s)))
            assert addresses and all(ipaddress.ip_address(x).is_global for x in addresses)
            pins[host] = addresses[0]
            RESULT['dns'].append(dict(host=host, resolver='HPC_login_system',
                public_ipv4_addresses=addresses, selected_once=pins[host], getaddrinfo_calls=1,
                server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
        connection = http.client.HTTPSConnection(host, 443, timeout=30, context=context)

        def connect_fixed(address, timeout=socket._GLOBAL_DEFAULT_TIMEOUT, source_address=None):
            assert address == (host, 443) and source_address is None and 0 < timeout <= 30
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            try:
                sock.connect((pins[host], 443))
            except BaseException:
                sock.close()
                raise
            return sock

        connection._create_connection = connect_fixed
        began = time.monotonic()
        try:
            path = u.path + ('?' + u.query if u.query else '')
            connection.request('HEAD', path, headers={'User-Agent': 'china-glhymps2-route/1',
                                                      'Accept-Encoding': 'identity'})
            response = connection.getresponse()
            headers = response.getheaders()
            header_size = sum(len(k.encode('latin1')) + len(v.encode('latin1')) + 4 for k, v in headers)
            assert header_size <= 65536 and response.getheader('Content-Encoding', 'identity') == 'identity'
            row.update(status=response.status, declared_length=response.getheader('Content-Length'),
                       content_type=response.getheader('Content-Type'), parsed_header_bytes=header_size,
                       connected_ipv4=pins[host], original_hostname_TLS_verified=True,
                       response_body_read_calls=0)
            if response.status in (301, 302, 303, 307, 308):
                redirect = urljoin(url, response.getheader('Location'))
                _, next_host = allowed(redirect)
                row.update(redirect_host=next_host, redirect_url_sha256=hashlib.sha256(redirect.encode()).hexdigest())
                url = redirect
                continue
            assert response.status == 200 and row['declared_length'] == str(2595563951), 'Exact original HEAD length'
            return dict(pins=pins, final_host=host)
        finally:
            row['seconds'] = time.monotonic() - began
            connection.close()
    raise RuntimeError('Finite HEAD chain exhausted')


try:
    candidate = main()
except BaseException as error:
    RESULT['complete'] = False
    RESULT['error'] = dict(type=type(error).__name__, message=str(error)[:600])
finally:
    elapsed = time.monotonic() - START
    if elapsed >= 100:
        RESULT.update(complete=False, error=dict(type='TimeoutError', message='HEAD/DNS main exceeded100seconds'))
    signal.setitimer(signal.ITIMER_REAL, 0)
    if 'error' not in RESULT:
        RESULT.update(candidate, complete=True)
    RESULT.update(server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), seconds=elapsed,
                  socket_timeout_seconds=30, whole_DNS_HEAD_seconds=100)
    raw = json.dumps(RESULT, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()
    assert len(raw) <= 2097152
    print('GEOLOGY_RECOVERY_BYTES=' + str(len(raw)))
    print('GEOLOGY_RECOVERY_SHA256=' + hashlib.sha256(raw).hexdigest())
    print('GEOLOGY_RECOVERY_ZLIB_BASE64=' + base64.b64encode(zlib.compress(raw)).decode())
    print('GEOLOGY_RECOVERY_DONE')

GLHYMPS2_DNS_ROUTE
