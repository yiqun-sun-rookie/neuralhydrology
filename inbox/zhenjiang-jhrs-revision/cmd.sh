#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInpoZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFvaklGSmxZV1F0YjI1c2VUb2djM1JoZEdVZ2IyWWdkR2hsSUVneElITnRiMnRsSUdGdVpDQmhjbkpoZVNCcWIySnpMQ0JoYm1RZ1kyOTFiblJ6SUc5bUlHWnBibWx6YUdWa0lIUmhjMnR6TGdwelpYUWdMWFVLVTB3OUwzVnpjaTlzYjJOaGJDOW5iRzlpYkdVdmMyOW1kSE12YzJ4MWNtMHZNVGt1TURVdU5DNHhMMkpwYmdwU1QwOVVQU0lrU0ZCRFgxQlNUMHBGUTFSZlVrOVBWQzlvTVY5Mk1TSUtaR0YwWlFwbFkyaHZJQ0lqSXlCeGRXVjFaU0k3SUNSVFRDOXpjWFZsZFdVZ0xXb2dNalU0TWpJd0xESTFPREl5TVNBdGFDQXRieUFpSldrZ0pWUWdKVTBnSlZJaUlESStKakVnZkNCb1pXRmtJQzB5TUFwbFkyaHZJQ0lqSXlCaFkyTnZkVzUwYVc1bklqc2dKRk5NTDNOaFkyTjBJQzFxSURJMU9ESXlNQ3d5TlRneU1qRWdMVmdnTFc0Z0xWQWdMUzFtYjNKdFlYUTlTbTlpU1VRc1UzUmhkR1VzUld4aGNITmxaQ3hPYjJSbFRHbHpkQ0F5UGlZeElId2dZWGRySUMxR0ozd25JQ2Q3YzFza01sMHJLMzBnUlU1RUlIdG1iM0lnS0dzZ2FXNGdjeWtnY0hKcGJuUWdheXdnYzF0clhYMG5DbVZqYUc4Z0lpTWpJSE50YjJ0bElqc2diSE1nSWlSU1QwOVVMM050YjJ0bFgzUmhjMnR6SWlBeVBpOWtaWFl2Ym5Wc2JEc2diSE1nSWlSU1QwOVVJaTl6Ylc5clpWOTBZWE5yY3k4cUx5QXlQaTlrWlhZdmJuVnNiQ0I4SUdobFlXUWdMVGdLZEdGcGJDQXROQ0FpSkZKUFQxUWlMMnh2WjNNdmFtaHljMTlvTVY5emJXOXJaVjhxWHpVM05pNXZkWFFnTWo0dlpHVjJMMjUxYkd3N0lIUmhhV3dnTFRNZ0lpUlNUMDlVSWk5c2IyZHpMMnBvY25OZmFERmZjMjF2YTJWZktsODFOell1WlhKeUlESStMMlJsZGk5dWRXeHNDbVZqYUc4Z0lpTWpJR2d4SUhSaGMydHpJR052YlhCc1pYUmxPaUFrS0d4eklDSWtVazlQVkNJdmFERmZkR0Z6YTNNdktpOWpiMjF3YkdWMGFXOXVYMjFoYm1sbVpYTjBMbXB6YjI0Z01qNHZaR1YyTDI1MWJHd2dmQ0IzWXlBdGJDa2lDZz09IiwKICAiY29tbWFuZF9zaGEyNTYiOiAiYmE2YWIxYTExNTkyODc0ZDQ4NGQyMjRmZmRhODQ5OWEyMjEwOTc3NTZkOTJhMThhNDJhY2JmYzdmNTc4YWYyNiIsCiAgInBheWxvYWRfcGF0aCI6IG51bGwsCiAgInBheWxvYWRfc2hhMjU2IjogbnVsbCwKICAicHJvamVjdF9pZCI6ICJ6aGVuamlhbmctamhycy1yZXZpc2lvbiIsCiAgInByb3RlY3RlZF9yZW1vdGVfcm9vdHMiOiBbCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uXzIwMjYxMDA2XzAwMiIsCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uX2ZpeGVkMjAwXzIwMjYxMDE5XzAwMyIKICBdLAogICJwcm90b2NvbCI6ICJjb25maWd1cmFibGUtaHBjLW1haWxib3gtdjEiLAogICJyZW1vdGVfcHl0aG9uIjogInB5dGhvbjMiLAogICJyZW1vdGVfcm9vdCI6ICIvZGF0YTEvaG9tZS9zdW55aXEvaHBjX3Byb2plY3RzL3poZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAicmVxdWVzdF9pZCI6ICJzdGF0dXMtaDEtMDAyIiwKICAic2VxdWVuY2UiOiAxMAp9Cg=='))
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
