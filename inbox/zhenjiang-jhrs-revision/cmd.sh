#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInpoZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFvaklGSmxjM1ZpYldsMElIUm9aU0J5WlhOMElHOW1JSE5sWldRZ09UY2dLSFJoYzJzZ2FXNWthV05sY3lBMU9EVXROamN4S1NCdmJpQm9aM0IxT0NCaFpuUmxjaUIwYUdVZ2IzWmxjaTFpY205aFpDQmpZVzVqWld3dUlGTmhiV1VnYW05aUlITmpjbWx3ZEN3Z2MyRnRaU0J2ZFhSd2RYUWdjbTl2ZEM0S2MyVjBJQzFsZFFwVFREMHZkWE55TDJ4dlkyRnNMMmRzYjJKc1pTOXpiMlowY3k5emJIVnliUzh4T1M0d05TNDBMakV2WW1sdUNsSlBUMVE5SWlSSVVFTmZVRkpQU2tWRFZGOVNUMDlVTDJneFgzWXhJZ3BqWkNBaUpGSlBUMVFpQ21SaGRHVUthV1lnSkZOTUwzTnhkV1YxWlNBdGRTQWlKRlZUUlZJaUlDMW9JQzF1SUdwb2NuTmZhREVnTFc4Z0lpVnBJaUI4SUdkeVpYQWdMWEVnTGpzZ2RHaGxiaUJsWTJodklDSktTRkpUWDBneFgwcFBRbE5mVTFSSlRFeGZVVlZGVlVWRUlqc2dKRk5NTDNOeGRXVjFaU0F0ZFNBaUpGVlRSVklpSUMxb0lDMXVJR3BvY25OZmFERWdMVzhnSWlWcElDVlVJanNnWlhocGRDQXhPeUJtYVFwd2NtVnpaVzUwUFNRb2NIbDBhRzl1TXlBdElEdzhKMUJaSndwcGJYQnZjblFnYjNNS2JtRnRaWE1nUFNCdmN5NXNhWE4wWkdseUtDSm9NVjkwWVhOcmN5SXBDbkJ5YVc1MEtITjFiU2d4SUdadmNpQnVJR2x1SUc1aGJXVnpJR2xtSUc0dVpXNWtjM2RwZEdnb0tDSnpaV1ZrWHprM0lpd3BLU2twQ2xCWkNpa0taV05vYnlBaWMyVmxaQ0E1TnlCMFlYTnJJR1JwY21WamRHOXlhV1Z6SUhCeVpYTmxiblE2SUNSN2NISmxjMlZ1ZEgwaUNrcFBRajBrS0NSVFRDOXpZbUYwWTJnZ0xTMXdZWEp6WVdKc1pTQXRMV0Z5Y21GNVBUVTROUzAyTnpFbE1UWWdhbWh5YzE5b01TNXpiSFZ5YlNrS1pXTm9ieUFpY21WemRXSnRhWFIwWldRZ1lYSnlZWGs5Skh0S1QwSjlJR2x1WkdsalpYTWdOVGcxTFRZM01TSUtjMnhsWlhBZ01qc2dKRk5NTDNOeGRXVjFaU0F0YWlBaUpIdEtUMEo5SWlBdGFDQXRieUFpSldrZ0pWUWdKVklpSUh3Z2FHVmhaQ0F0TkFvPSIsCiAgImNvbW1hbmRfc2hhMjU2IjogIjkyZDk5YWQ5ZTY3ODI0ZTE5YmViNzE2NjQ2N2Q2N2NiYjY5MmE0OWFhOTI3NzBlMzMyMDcyNmUwZWJjYmNkNDkiLAogICJwYXlsb2FkX3BhdGgiOiBudWxsLAogICJwYXlsb2FkX3NoYTI1NiI6IG51bGwsCiAgInByb2plY3RfaWQiOiAiemhlbmppYW5nLWpocnMtcmV2aXNpb24iLAogICJwcm90ZWN0ZWRfcmVtb3RlX3Jvb3RzIjogWwogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDIiLAogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMiCiAgXSwKICAicHJvdG9jb2wiOiAiY29uZmlndXJhYmxlLWhwYy1tYWlsYm94LXYxIiwKICAicmVtb3RlX3B5dGhvbiI6ICJweXRob24zIiwKICAicmVtb3RlX3Jvb3QiOiAiL2RhdGExL2hvbWUvc3VueWlxL2hwY19wcm9qZWN0cy96aGVuamlhbmctamhycy1yZXZpc2lvbiIsCiAgInJlcXVlc3RfaWQiOiAicmVzdWJtaXQtc2VlZDk3LXJlc3QiLAogICJzZXF1ZW5jZSI6IDE1Cn0K'))
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
