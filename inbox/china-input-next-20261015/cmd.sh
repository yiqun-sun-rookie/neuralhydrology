#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 160s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'OPEN_ALTERNATIVES'
"""One finite HPC public-directory session; no GIS, source archives or Slurm."""
import base64
import datetime
import hashlib
import io
import sys
from http.client import HTTPResponse, IncompleteRead
import json
import re
import resource
import signal
import time
from html.parser import HTMLParser
from urllib.error import HTTPError
from urllib.parse import urljoin, urlparse
from urllib.request import build_opener, HTTPRedirectHandler, ProxyHandler, Request
import zlib

START = time.monotonic()
ENDPOINTS = [
    ('USGS_ORIGINAL_METADATA', 'https://data.usgs.gov/datacatalog/metadata/USGS.60abc7f9d34ea221ce51e5ee.xml'),
    ('USGS_ORIGINAL_CATALOGUE', 'https://www.sciencebase.gov/catalog/item/60abc7f9d34ea221ce51e5ee?format=json'),
    ('WWHYPDA_RELEASE', 'https://zenodo.org/api/records/7974404'),
    ('WWHYPDA_AUTHOR_TREE', 'https://api.github.com/repos/alecomunian/wwhypda/git/trees/master?recursive=1'),
]


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []; self.titles = []; self.in_title = False; self.forms = []; self.scripts = []

    def handle_starttag(self, tag, attrs):
        self.in_title = self.in_title or tag.lower() == 'title'
        if tag.lower() == 'a' and len(self.links) < 100:
            href = dict(attrs).get('href')
            if href is not None and len(href) <= 2048:
                self.links.append(href)

        attrs = dict(attrs)
        if tag.lower() == 'form' and len(self.forms) < 40:
            self.forms.append(dict(action=attrs.get('action'), method=attrs.get('method')))
        if tag.lower() == 'script' and attrs.get('src') and len(self.scripts) < 40:
            self.scripts.append(attrs['src'][:2048])

    def handle_endtag(self, tag):
        if tag.lower() == 'title': self.in_title = False

    def handle_data(self, value):
        if self.in_title and len(self.titles) < 20: self.titles.append(value[:1000])


def expired(*_):
    raise TimeoutError('Frozen public metadata deadline')


def allowed(url, name):
    assert (name, url) in ENDPOINTS, 'Only exact reviewed metadata endpoints'
    p = urlparse(url)
    assert p.scheme == 'https' and p.port in (None, 443)
    assert p.username is None and p.password is None and not p.fragment


def main():
    resource.setrlimit(resource.RLIMIT_AS, (256 * 1024**2, resource.getrlimit(resource.RLIMIT_AS)[1]))
    signal.signal(signal.SIGALRM, expired)
    result = dict(kind='GAP27888_OPEN_ALTERNATIVES', member='27888',
        complete=False, metadata_session_finished=False, responses=[], documents=[],
        new_jobs=0, source_content_reads=0, source_decoding=0, source_writes=0,
        scientific_archives_downloaded=0, model_calls=0, automatic_checks_enabled=False,
        scientific_input_accepted=False, prediction_approved=False,
        permeability_units_verified=False, porosity_units_verified=False,
        member_coverage='UNKNOWN_NOT_SPATIALLY_COMPUTED')
    opener = build_opener(ProxyHandler({}), NoRedirect())
    total = 0; requests = 0
    for name, initial in ENDPOINTS:
        url = initial; doc = dict(name=name, initial_url=initial, acquired=False)
        result['documents'].append(doc)
        for hop in range(1):
            assert requests < 4 and total <= 1024**2
            remaining = 150 - (time.monotonic() - START)
            if remaining <= 1 or total == 1024**2:
                doc['error'] = 'FROZEN_SESSION_LIMIT'; break
            allowed(url, name); requests += 1
            limit = min(30, remaining - 1); began = time.monotonic()
            row = dict(name=name, hop=hop, url=url, status=None, complete=False)
            result['responses'].append(row); response = None; raw = b''
            signal.setitimer(signal.ITIMER_REAL, limit)
            try:
                req = Request(url, headers={'User-Agent':'china-gap27888-public-directory/1',
                                            'Accept-Encoding':'identity'})
                try: response = opener.open(req, timeout=limit)
                except HTTPError as error: response = error
                row.update(status=response.code, content_type=response.headers.get('Content-Type'),
                    declared_length=response.headers.get('Content-Length'),
                    content_encoding=response.headers.get('Content-Encoding', 'identity'),
                    location=response.headers.get('Location'),
                    transfer_encoding=response.headers.get('Transfer-Encoding'),
                    http_version=getattr(response, 'version', None),
                    library_chunked=getattr(response, 'chunked', False))
                assert row['content_encoding'] == 'identity', 'Compressed metadata not accepted'
                typ = (row['content_type'] or '').split(';')[0].strip().lower()
                assert typ.startswith('text/') or typ in ('application/json','application/vnd.api+json',
                    'application/xml','application/xhtml+xml','application/javascript','application/x-javascript'), 'Metadata text only'
                cap = min(512 * 1024, 1024**2 - total)
                declared = row['declared_length']
                transfer = (row['transfer_encoding'] or '').strip().lower()
                if declared is not None:
                    assert not transfer, 'Ambiguous CL plus Transfer-Encoding rejected'
                    assert 0 <= int(declared) <= cap, 'Exact declared metadata body budget'
                    row['framing'] = 'CONTENT_LENGTH'
                else:
                    assert transfer=='chunked' and row['library_chunked'] is True, 'Unverified no-length framing'
                    row['framing'] = 'CHUNKED'
                try:
                    raw = response.read(cap)
                except IncompleteRead as error:
                    raw = error.partial
                    total += len(raw)
                    row.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                        base64=base64.b64encode(raw).decode(), partial_body=True)
                    raise
                total += len(raw)
                row.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                           base64=base64.b64encode(raw).decode())
                if declared is not None:
                    assert len(raw)==int(declared), 'Metadata length mismatch'
                else:
                    row.update(response_closed_after_read=response.isclosed(),
                        chunk_left_after_read=response.chunk_left)
                    assert len(raw)<cap and row['response_closed_after_read'] is True and response.chunk_left is None, 'No validated terminal chunk or body cap reached'
                row['framing_complete'] = True
                response.close(); response = None
                assert time.monotonic() - began < limit, 'Request time limit after close'
                row['complete'] = True
            except MemoryError:
                raise
            except Exception as error:
                row['error'] = dict(type=type(error).__name__, message=str(error)[:700])
            finally:
                try:
                    if response is not None: response.close()
                except Exception as error:
                    row['complete'] = False
                    row['close_error'] = repr(error)[:700]
                finally:
                    signal.setitimer(signal.ITIMER_REAL, 0)
                row['seconds'] = time.monotonic() - began
                if row['seconds'] >= limit:
                    row['complete'] = False; row['time_gate_failed'] = True
            if not row['complete']: break
            if row['status'] in (301,302,303,307,308) and row['location']:
                try:
                    target = urljoin(url, row['location']); allowed(target, name)
                    if urlparse(url).scheme == 'https': assert urlparse(target).scheme == 'https', 'No TLS downgrade'
                    row['redirect_target'] = target
                except MemoryError:
                    raise
                except Exception as error:
                    row['redirect_validation_error'] = repr(error)[:700]
                    doc['error'] = 'REDIRECT_NOT_FOLLOWED'
                    break
                if hop == 0: doc['error'] = 'NO_REDIRECT_AUTHORIZED'; break
                url = target; continue
            if row['status'] != 200:
                doc['error'] = 'HTTP_STATUS_' + str(row['status']); break
            try:
                text = raw.decode('utf8', errors='replace')
                parser = Links(); parser.feed(text)
            except MemoryError:
                raise
            except Exception as error:
                doc['error'] = 'SOURCE_DOCUMENT_PARSE_ERROR'
                doc['parse_error'] = repr(error)[:700]
                break
            doc.update(acquired=True, final_url=url, response_index=len(result['responses'])-1,
                title=' '.join(parser.titles), links=parser.links, forms=parser.forms, script_urls=parser.scripts,
                excerpt=text[:5000], semantic_admission='UNKNOWN_MANUAL_ORIGINAL_REVIEW_REQUIRED')

            break
    result.update(metadata_session_finished=True, requests=requests, received_body_bytes=total,
        server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), seconds=time.monotonic()-START)
    assert result['seconds'] < 150 and requests <= 4 and total <= 1024**2
    result['complete'] = all(d['acquired'] for d in result['documents'])
    return result


if __name__ == '__main__':
    value = main()
    raw = (json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',',':'))+'\n').encode()
    assert len(raw) <= 4*1024**2 and time.monotonic()-START < 150
    encoded = base64.b64encode(zlib.compress(raw)).decode()
    assert time.monotonic()-START < 150
    print('GEOLOGY_RECOVERY_BYTES='+str(len(raw)))
    print('GEOLOGY_RECOVERY_SHA256='+hashlib.sha256(raw).hexdigest())
    print('GEOLOGY_RECOVERY_ZLIB_BASE64='+encoded)
    print('GEOLOGY_RECOVERY_DONE', flush=True)
    assert time.monotonic()-START < 150, 'Final output/flush deadline exceeded; nonzero exit'

OPEN_ALTERNATIVES
