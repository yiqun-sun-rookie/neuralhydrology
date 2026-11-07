#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInpoZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFvaklGSmxZV1F0YjI1c2VUb2dabkpsWlNCSFVGVnpJSEJsY2lCdWIyUmxJR0Z1WkNCbGMzUnBiV0YwWldRZ2MzUmhjblFnY0dWeUlIQmhjblJwZEdsdmJpNGdVM1ZpYldsMGN5QnViM1JvYVc1bklDaHpZbUYwWTJnZ0xTMTBaWE4wTFc5dWJIa2diMjVzZVNrdUNuTmxkQ0F0ZFFwVFREMHZkWE55TDJ4dlkyRnNMMmRzYjJKc1pTOXpiMlowY3k5emJIVnliUzh4T1M0d05TNDBMakV2WW1sdUNtVmphRzhnSWlNaklHUmhkR1VpT3lCa1lYUmxDbVZqYUc4Z0lpTWpJR2R3ZFNCd1pYSWdibTlrWlRvZ1kyOXVabWxuZFhKbFpDQjJjeUJoYkd4dlkyRjBaV1FpQ2lSVFRDOXpZMjl1ZEhKdmJDQnphRzkzSUc1dlpHVWdNajR2WkdWMkwyNTFiR3dnZkNCaGQyc2dKeTllVG05a1pVNWhiV1U5TDN0dVBTUXhPeUJ6UFNJaWZTQXZVM1JoZEdVOUwzdG1iM0lvYVQweE8yazhQVTVHTzJrckt5a2dhV1lvSkdrZ2ZpQXZYbE4wWVhSbFBTOHBJSE05SkdsOUlDOVFZWEowYVhScGIyNXpQUzk3Y0Qwa01YMGdMME5tWjFSU1JWTTlMM3RqUFNReGZTQXZRV3hzYjJOVVVrVlRQUzk3Y0hKcGJuUWdiaXdnY0N3Z2N5d2dZeXdnSkRGOUp5QjhJR2R5WlhBZ0xVVWdJbWhuY0hVaUlId2djMlZrSUNkekwwTm1aMVJTUlZNOUx5ODdJSE12UVd4c2IyTlVVa1ZUUFM4dkp5QjhJR2hsWVdRZ0xUUXdDbVZqYUc4Z0lpTWpJRzkzYmlCeGRXVjFaU0lLSkZOTUwzTnhkV1YxWlNBdGRTQWlKRlZUUlZJaUlDMW9JQzF2SUNJbGFTQWxVQ0FsVkNBbFRTQWxVaUlnTWo0bU1TQjhJR2hsWVdRZ0xUSXdDbVZqYUc4Z0lpTWpJR1Z6ZEdsdFlYUmxaQ0J6ZEdGeWRDQm1iM0lnYjI1bElFZFFWU3dnYm05MGFHbHVaeUJ6ZFdKdGFYUjBaV1FpQ21admNpQndJR2x1SUdobmNIVTRJR2huY0hVMElHaG5jSFV5Y0NCb1ozQjFNanNnWkc4S0lDQmxZMmh2SUNJdExTQWtjQ0lLSUNCMGFXMWxiM1YwSURJd0lDUlRUQzl6WW1GMFkyZ2dMUzEwWlhOMExXOXViSGtnTFhBZ0lpUndJaUF0VGlBeElDMXVJREVnTFMxamNIVnpMWEJsY2kxMFlYTnJQVFFnTFMxbmNtVnpQV2R3ZFRveElDMTBJREF3T2pVd09qQXdJQzB0ZDNKaGNEMTBjblZsSURJK0pqRWdmQ0IwWVdsc0lDMHhDbVJ2Ym1VS1pXTm9ieUFpSXlNZ2NtVnpaWEoyWVhScGIyNXpJanNnSkZOTUwzTmpiMjUwY205c0lITm9iM2NnY21WelpYSjJZWFJwYjI0Z01qNG1NU0I4SUdobFlXUWdMVGdLIiwKICAiY29tbWFuZF9zaGEyNTYiOiAiOWQxYTI2MjQyNDYyYmQzMjY5ZDUyNTFjNTI5NjQ5N2MwNDE1YTI2ZjkyNzU2MWQxMmE5YWFiNWM1ZDdkNGU5OSIsCiAgInBheWxvYWRfcGF0aCI6IG51bGwsCiAgInBheWxvYWRfc2hhMjU2IjogbnVsbCwKICAicHJvamVjdF9pZCI6ICJ6aGVuamlhbmctamhycy1yZXZpc2lvbiIsCiAgInByb3RlY3RlZF9yZW1vdGVfcm9vdHMiOiBbCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uXzIwMjYxMDA2XzAwMiIsCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uX2ZpeGVkMjAwXzIwMjYxMDE5XzAwMyIKICBdLAogICJwcm90b2NvbCI6ICJjb25maWd1cmFibGUtaHBjLW1haWxib3gtdjEiLAogICJyZW1vdGVfcHl0aG9uIjogInB5dGhvbjMiLAogICJyZW1vdGVfcm9vdCI6ICIvZGF0YTEvaG9tZS9zdW55aXEvaHBjX3Byb2plY3RzL3poZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAicmVxdWVzdF9pZCI6ICJyZXNvdXJjZXMtMDA0IiwKICAic2VxdWVuY2UiOiA1Cn0K'))
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
