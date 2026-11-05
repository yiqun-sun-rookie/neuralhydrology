#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInByZWNpcC1yMTYtcmVzb3VyY2Utc3RhdHVzLTIwMjYxMTA1IiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFwelpYUWdMV1VLY0hsMGFHOXVNeUF0SUR3OEoxQlpKd3BtY205dElHUmhkR1YwYVcxbElHbHRjRzl5ZENCa1lYUmxkR2x0WlFwcGJYQnZjblFnYW5OdmJncG1jbTl0SUhCaGRHaHNhV0lnYVcxd2IzSjBJRkJoZEdnS2FXMXdiM0owSUhOMVluQnliMk5sYzNNS2NtOXZkRDBuTDNWemNpOXNiMk5oYkM5bmJHOWliR1V2YzI5bWRITXZjMngxY20wdk1Ua3VNRFV1TkM0eEwySnBiaThuQ25CaGNuUnBkR2x2Ym5NOUoyaG5jSFV5Y0N4b1ozQjFNaXhvWjNCMU5DeG9aM0IxT0NjS1kyOXRiV0Z1WkhNOWV3b2dKMmR3ZFY5dWIyUmxjeWM2VzNKdmIzUXJKM05wYm1adkp5d25MVTRuTENjdGFDY3NKeTF3Snl4d1lYSjBhWFJwYjI1ekxDY3RieWNzSnlWUWZDVk9mQ1YwZkNWSGZDVkRKMTBzQ2lBblozQjFYM1Z6WVdkbEp6cGJjbTl2ZENzbmMybHVabThuTENjdFRpY3NKeTF3Snl4d1lYSjBhWFJwYjI1ekxDY3RUeWNzSjI1dlpHVnNhWE4wT2pFMExHZHlaWE02TWpBc1ozSmxjM1Z6WldRNk16SXNZM0IxYzNOMFlYUmxPakkwSjEwc0NpQW5iM2R1WDJwdlluTW5PbHR5YjI5MEt5ZHpjWFZsZFdVbkxDY3RkU2NzSjNOMWJubHBjU2NzSnkxb0p5d25MVzhuTENjbGFYd2xVSHdsYW53bFZId2xUWHdsYkh3bFJId2xVaWRkZlFweVpYTjFiSFE5ZXlkamFHVmphMlZrWDNWMFl5YzZaR0YwWlhScGJXVXVkWFJqYm05M0tDa3VhWE52Wm05eWJXRjBLQ2tySjFvbkxDZHpkV0p0YVhSMFpXUmZhbTlpY3ljNk1Dd25iVzlrWld4ZlkyRnNiSE1uT2pCOUNtWnZjaUJ1WVcxbExHTnZiVzFoYm1RZ2FXNGdZMjl0YldGdVpITXVhWFJsYlhNb0tUb0tJSEE5YzNWaWNISnZZMlZ6Y3k1eWRXNG9ZMjl0YldGdVpDeHpkR1J2ZFhROWMzVmljSEp2WTJWemN5NVFTVkJGTEhOMFpHVnljajF6ZFdKd2NtOWpaWE56TGxCSlVFVXNkVzVwZG1WeWMyRnNYMjVsZDJ4cGJtVnpQVlJ5ZFdVc2RHbHRaVzkxZEQweU5Ta0tJSEpsYzNWc2RGdHVZVzFsWFQxN0oyVjRhWFJmWTI5a1pTYzZjQzV5WlhSMWNtNWpiMlJsTENkemRHUnZkWFFuT25BdWMzUmtiM1YwV3pvMk1EQXdNRjBzSjNOMFpHVnljaWM2Y0M1emRHUmxjbkpiT2pRd01EQmRmUXB3Y21sdWRDaHFjMjl1TG1SMWJYQnpLSEpsYzNWc2RDa3BDbEJaQ2c9PSIsCiAgImNvbW1hbmRfc2hhMjU2IjogIjI5ZDJhYTFlYWQwNGJmNmViNDczNTIxMTI2YjlmZDQ4ZDI3YmIxNmQ3OGE3M2U4OTcyOWIzMmJjZTI3OTAzNzEiLAogICJwYXlsb2FkX3BhdGgiOiBudWxsLAogICJwYXlsb2FkX3NoYTI1NiI6IG51bGwsCiAgInByb2plY3RfaWQiOiAicHJlY2lwLXIxNi1yZXNvdXJjZS1zdGF0dXMtMjAyNjExMDUiLAogICJwcm90ZWN0ZWRfcmVtb3RlX3Jvb3RzIjogWwogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDIiLAogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMiCiAgXSwKICAicHJvdG9jb2wiOiAiY29uZmlndXJhYmxlLWhwYy1tYWlsYm94LXYxIiwKICAicmVtb3RlX3B5dGhvbiI6ICJweXRob24zIiwKICAicmVtb3RlX3Jvb3QiOiAiL2RhdGExL2hvbWUvc3VueWlxL2hwY19wcm9qZWN0cy9wcmVjaXBfcjE2X3Jlc291cmNlX3N0YXR1c18yMDI2MTEwNSIsCiAgInJlcXVlc3RfaWQiOiAicmVzb3VyY2Utc3RhdHVzLTIwMjYxMTA1LTE2MDAtdjAxIiwKICAic2VxdWVuY2UiOiAxCn0K'))
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
