#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInByZWNpcC1yMTYtcmVzb3VyY2Utc3RhdHVzLTIwMjYxMTA1IiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFwelpYUWdMV1VLY0hsMGFHOXVNeUF0SUR3OEoxQlpKd3BtY205dElHUmhkR1YwYVcxbElHbHRjRzl5ZENCa1lYUmxkR2x0WlFwcGJYQnZjblFnYW5OdmJncHBiWEJ2Y25RZ2MzVmljSEp2WTJWemN3cHliMjkwUFNjdmRYTnlMMnh2WTJGc0wyZHNiMkpzWlM5emIyWjBjeTl6YkhWeWJTOHhPUzR3TlM0MExqRXZZbWx1THljS2NHRnlkR2wwYVc5dWN6MG5hR2R3ZFRKd0xHaG5jSFV5TEdobmNIVTBMR2huY0hVNEp3cGpiMjF0WVc1a2N6MTdDaUFuWjNCMVgyNXZaR1Z6SnpwYmNtOXZkQ3NuYzJsdVptOG5MQ2N0VGljc0p5MW9KeXduTFhBbkxIQmhjblJwZEdsdmJuTXNKeTF2Snl3bkpWQjhKVTU4SlhSOEpVZDhKVU1uWFN3S0lDZG5jSFZmZFhOaFoyVW5PbHR5YjI5MEt5ZHphVzVtYnljc0p5MU9KeXduTFhBbkxIQmhjblJwZEdsdmJuTXNKeTFQSnl3bmJtOWtaV3hwYzNRNk1UUXNaM0psY3pveU1DeG5jbVZ6ZFhObFpEb3pNaXhqY0hWemMzUmhkR1U2TWpRblhTd0tJQ2R2ZDI1ZmFtOWljeWM2VzNKdmIzUXJKM054ZFdWMVpTY3NKeTExSnl3bmMzVnVlV2x4Snl3bkxXZ25MQ2N0Ynljc0p5VnBmQ1ZRZkNWcWZDVlVmQ1ZOZkNWc2ZDVkVmQ1ZTSjEwc0NpQW5jMmx1WjJ4bFgyZHdkVjl6WTJobFpIVnNhVzVuWDJWemRHbHRZWFJsSnpwYmNtOXZkQ3NuYzJKaGRHTm9KeXduTFMxMFpYTjBMVzl1YkhrbkxDY3RMVzV2WkdWelBURW5MQ2N0TFc1MFlYTnJjejB4Snl3S0lDQWdJQ0FuTFMxamNIVnpMWEJsY2kxMFlYTnJQVEluTENjdExXZHlaWE05WjNCMU9qRW5MQ2N0TFhScGJXVTlNRFk2TURBNk1EQW5MQ2N0TFhCaGNuUnBkR2x2Ymoxb1ozQjFOQ3hvWjNCMU1uQXNhR2R3ZFRJbkxBb2dJQ0FnSUNjdExXcHZZaTF1WVcxbFBYQnlaV05wY0Y5eU1UWmZjMk5vWldSMWJHVmZiMjVzZVNjc0p5MHRkM0poY0QxMGNuVmxKMTE5Q25KbGMzVnNkRDE3SjJOb1pXTnJaV1JmZFhSakp6cGtZWFJsZEdsdFpTNTFkR051YjNjb0tTNXBjMjltYjNKdFlYUW9LU3NuV2ljc0ozTjFZbTFwZEhSbFpGOXFiMkp6Snpvd0xDZHRiMlJsYkY5allXeHNjeWM2TUN3S0lDQWdJQ0FnSUNBbmMyTm9aV1IxYkdsdVoxOXdjbTlpWlNjNkoxTnNkWEp0SUhSbGMzUXRiMjVzZVN3Z01TQkhVRlVnTHlBeUlFTlFWU0F2SURab095QnVieUJxYjJJZ2IzSWdjbVZ6YjNWeVkyVWdZV3hzYjJOaGRHbHZiaWQ5Q21admNpQnVZVzFsTEdOdmJXMWhibVFnYVc0Z1kyOXRiV0Z1WkhNdWFYUmxiWE1vS1RvS0lIUnllVG9LSUNCd1BYTjFZbkJ5YjJObGMzTXVjblZ1S0dOdmJXMWhibVFzYzNSa2IzVjBQWE4xWW5CeWIyTmxjM011VUVsUVJTeHpkR1JsY25JOWMzVmljSEp2WTJWemN5NVFTVkJGTEhWdWFYWmxjbk5oYkY5dVpYZHNhVzVsY3oxVWNuVmxMSFJwYldWdmRYUTlNekFwQ2lBZ2NtVnpkV3gwVzI1aGJXVmRQWHNuWlhocGRGOWpiMlJsSnpwd0xuSmxkSFZ5Ym1OdlpHVXNKM04wWkc5MWRDYzZjQzV6ZEdSdmRYUmJPall3TURBd1hTd25jM1JrWlhKeUp6cHdMbk4wWkdWeWNsczZOREF3TUYxOUNpQmxlR05sY0hRZ2MzVmljSEp2WTJWemN5NVVhVzFsYjNWMFJYaHdhWEpsWkRvS0lDQnlaWE4xYkhSYmJtRnRaVjA5ZXlkemRHRjBaU2M2SjFSSlRVVlBWVlFuTENkMGFXMWxiM1YwWDNObFkyOXVaSE1uT2pNd2ZRcHdjbWx1ZENocWMyOXVMbVIxYlhCektISmxjM1ZzZENrcENsQlpDZz09IiwKICAiY29tbWFuZF9zaGEyNTYiOiAiN2JjNzc3OGEzOGIzOGZhYjBhMjcxZDRmOGQ3MWY3ZWFkZWEwYjAyMzcwNGI1ZDNhYTQ0NmExNDJkODdiMGViOSIsCiAgInBheWxvYWRfcGF0aCI6IG51bGwsCiAgInBheWxvYWRfc2hhMjU2IjogbnVsbCwKICAicHJvamVjdF9pZCI6ICJwcmVjaXAtcjE2LXJlc291cmNlLXN0YXR1cy0yMDI2MTEwNSIsCiAgInByb3RlY3RlZF9yZW1vdGVfcm9vdHMiOiBbCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uXzIwMjYxMDA2XzAwMiIsCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uX2ZpeGVkMjAwXzIwMjYxMDE5XzAwMyIKICBdLAogICJwcm90b2NvbCI6ICJjb25maWd1cmFibGUtaHBjLW1haWxib3gtdjEiLAogICJyZW1vdGVfcHl0aG9uIjogInB5dGhvbjMiLAogICJyZW1vdGVfcm9vdCI6ICIvZGF0YTEvaG9tZS9zdW55aXEvaHBjX3Byb2plY3RzL3ByZWNpcF9yMTZfcmVzb3VyY2Vfc3RhdHVzXzIwMjYxMTA1IiwKICAicmVxdWVzdF9pZCI6ICJyZXNvdXJjZS1xdWV1ZS0yMDI2MTEwNS0xODA3LXYwMiIsCiAgInNlcXVlbmNlIjogMgp9Cg=='))
root = pathlib.Path(s['remote_root']).resolve()
for old in s['protected_remote_roots']:
    p = pathlib.Path(old).resolve()
    if root == p or root in p.parents or p in root.parents:
        raise RuntimeError('Resolved work root overlaps a protected directory')
mailbox = pathlib.Path.cwd()
root.mkdir(parents=True, exist_ok=True)
area = root / '.hpc_mailbox' / (str(s['sequence']) + '_' + s['request_id'])
area.mkdir(parents=True, exist_ok=False)
payload_dir = area / 'payload'
payload_dir.mkdir()
if s['payload_path']:
    raw = (mailbox / s['payload_path']).read_bytes()
    if hashlib.sha256(raw).hexdigest() != s['payload_sha256']:
        raise RuntimeError('Payload checksum mismatch')
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz') as archive:
        seen = set()
        for m in archive:
            rel = pathlib.PurePosixPath(m.name)
            if (rel.is_absolute() or '..' in rel.parts or '\\' in m.name
                    or not (m.isfile() or m.isdir()) or str(rel) in seen):
                raise RuntimeError('Unsafe payload member')
            seen.add(str(rel))
            dest = payload_dir.joinpath(*rel.parts)
            if m.isdir():
                dest.mkdir(parents=True, exist_ok=True)
            else:
                dest.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(m) as src, dest.open('xb') as out:
                    import shutil
                    shutil.copyfileobj(src, out)
                dest.chmod(0o755 if m.mode & 0o111 else 0o644)
command = base64.b64decode(s['command_base64'])
if hashlib.sha256(command).hexdigest() != s['command_sha256']:
    raise RuntimeError('Command checksum mismatch')
task = area / 'task.sh'
task.write_bytes(command)
env = dict(os.environ, HPC_PROJECT_ID=s['project_id'], HPC_CHANNEL=s['channel'],
           HPC_REQUEST_ID=s['request_id'], HPC_REQUEST_SEQUENCE=str(s['sequence']),
           HPC_PROJECT_ROOT=str(root), HPC_REQUEST_DIR=str(area), HPC_PAYLOAD_DIR=str(payload_dir))
print(json.dumps({'hpc_mailbox_request': s['request_id'], 'project_id': s['project_id'],
                  'channel': s['channel'], 'sequence': s['sequence'], 'remote_root': str(root),
                  'payload_sha256': s['payload_sha256']}), flush=True)
returncode = subprocess.run(['bash', str(task)], cwd=str(root), env=env).returncode
print('', flush=True)
sys.exit(returncode)

HPC_MAILBOX_BOOTSTRAP
