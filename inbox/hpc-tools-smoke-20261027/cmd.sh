#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogImhwYy10b29scy1zbW9rZS0yMDI2MTAyNyIsCiAgImNvbW1hbmRfYmFzZTY0IjogIkl5RXZkWE55TDJKcGJpOWxibllnWW1GemFBcHpaWFFnTFdVS2NIbDBhRzl1TXlBdElEdzhKMUJTVDBKRkp3cHBiWEJ2Y25RZ2FHRnphR3hwWWl3Z2FuTnZiaXdnYjNNS1puSnZiU0J3WVhSb2JHbGlJR2x0Y0c5eWRDQlFZWFJvQ25CaGVXeHZZV1FnUFNBb1VHRjBhQ2h2Y3k1bGJuWnBjbTl1V3lkSVVFTmZVRUZaVEU5QlJGOUVTVkluWFNrZ0x5QW5iV1Z6YzJGblpTNTBlSFFuS1M1eVpXRmtYMko1ZEdWektDa0tZWE56WlhKMElIQmhlV3h2WVdRZ1BUMGdZaWRqYjI1bWFXZDFjbUZpYkdVZ2JXRnBiR0p2ZUNCd1lYbHNiMkZrSUhKdmRXNWtJSFJ5YVhCY2JpY0tZWE56WlhKMElGQmhkR2d1WTNka0tDa2dQVDBnVUdGMGFDaHZjeTVsYm5acGNtOXVXeWRJVUVOZlVGSlBTa1ZEVkY5U1QwOVVKMTBwQ25CeWFXNTBLR3B6YjI0dVpIVnRjSE1vZXlkd2NtOWlaU2M2SUNkUVFWTlRKeXdnSjNCeWIycGxZM1FuT2lCdmN5NWxiblpwY205dVd5ZElVRU5mVUZKUFNrVkRWRjlKUkNkZExDQW5ZMmhoYm01bGJDYzZJRzl6TG1WdWRtbHliMjViSjBoUVExOURTRUZPVGtWTUoxMHNJQ2RqZDJRbk9pQnpkSElvVUdGMGFDNWpkMlFvS1Nrc0lDZHdZWGxzYjJGa1gzTm9ZVEkxTmljNklHaGhjMmhzYVdJdWMyaGhNalUyS0hCaGVXeHZZV1FwTG1obGVHUnBaMlZ6ZENncExDQW5jMk5wWlc1MGFXWnBZMTlxYjJKelgzTjFZbTFwZEhSbFpDYzZJREI5S1NrS1VGSlBRa1VLIiwKICAiY29tbWFuZF9zaGEyNTYiOiAiOTE5OTIyYWM2MTY1MjJhNjZhYjM4NzVjMGU1NzhiYzM4ZTFlNDk3NDhlODQyZmJiMjIyNzg2YzlhMzJiN2JjYSIsCiAgInBheWxvYWRfcGF0aCI6ICJpbmJveC9ocGMtdG9vbHMtc21va2UtMjAyNjEwMjcvcGF5bG9hZF8xLnRhci5neiIsCiAgInBheWxvYWRfc2hhMjU2IjogImNlZjA4NDAzODFlNWU2MjE5NTEzN2NlNTRhYzk3OThjMzlhMDdlNGRhMTg3YTI0MDJhYzEzNDJiNWQyYTg1NmEiLAogICJwcm9qZWN0X2lkIjogImhwYy10b29scy1zbW9rZS0yMDI2MTAyNyIsCiAgInByb3RlY3RlZF9yZW1vdGVfcm9vdHMiOiBbCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uXzIwMjYxMDA2XzAwMiIsCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uX2ZpeGVkMjAwXzIwMjYxMDE5XzAwMyIKICBdLAogICJwcm90b2NvbCI6ICJjb25maWd1cmFibGUtaHBjLW1haWxib3gtdjEiLAogICJyZW1vdGVfcHl0aG9uIjogInB5dGhvbjMiLAogICJyZW1vdGVfcm9vdCI6ICIvZGF0YTEvaG9tZS9zdW55aXEvaHBjX3Byb2plY3RzL2hwYy10b29scy1zbW9rZS0yMDI2MTAyNyIsCiAgInJlcXVlc3RfaWQiOiAicm91bmR0cmlwLTAwMSIsCiAgInNlcXVlbmNlIjogMQp9Cg=='))
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
sys.exit(subprocess.run(['bash', str(task)], cwd=str(root), env=env).returncode)

HPC_MAILBOX_BOOTSTRAP
