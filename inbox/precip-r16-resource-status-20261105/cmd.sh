#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInByZWNpcC1yMTYtcmVzb3VyY2Utc3RhdHVzLTIwMjYxMTA1IiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFwelpYUWdMV1VLY0hsMGFHOXVNeUF0SUR3OEoxQlpKd3BtY205dElHUmhkR1YwYVcxbElHbHRjRzl5ZENCa1lYUmxkR2x0WlFwcGJYQnZjblFnYW5OdmJncG1jbTl0SUhCaGRHaHNhV0lnYVcxd2IzSjBJRkJoZEdnS2FXMXdiM0owSUhKbENtbHRjRzl5ZENCemRXSndjbTlqWlhOekNuSnZiM1E5Snk5MWMzSXZiRzlqWVd3dloyeHZZbXhsTDNOdlpuUnpMM05zZFhKdEx6RTVMakExTGpRdU1TOWlhVzR2Sndwd1lYSjBjejBuYUdkd2RUUXNhR2R3ZFRKd0xHaG5jSFV5TEdobmNIVTRKd3BqYjIxdFlXNWtjejE3Q2lBblozQjFYMjV2WkdWekp6cGJjbTl2ZENzbmMybHVabThuTENjdFRpY3NKeTFvSnl3bkxYQW5MSEJoY25SekxDY3RieWNzSnlWUWZDVk9mQ1YwZkNWSGZDVkRKMTBzQ2lBblozQjFYM1Z6WVdkbEp6cGJjbTl2ZENzbmMybHVabThuTENjdFRpY3NKeTF3Snl4d1lYSjBjeXduTFU4bkxDZHViMlJsYkdsemREb3hOQ3huY21Wek9qSXdMR2R5WlhOMWMyVmtPak15TEdOd2RYTnpkR0YwWlRveU5DZGRMQW9nSjJGc2JGOW5jSFZmYzNSaGNuUmZaWE4wYVcxaGRHVW5PbHR5YjI5MEt5ZHpZbUYwWTJnbkxDY3RMWFJsYzNRdGIyNXNlU2NzSnkwdGJtOWtaWE05TVNjc0p5MHRiblJoYzJ0elBURW5MQ2N0TFdOd2RYTXRjR1Z5TFhSaGMyczlNaWNzQ2lBZ0lDQWdKeTB0WjNKbGN6MW5jSFU2TVNjc0p5MHRkR2x0WlQwd05qb3dNRG93TUNjc0p5MHRjR0Z5ZEdsMGFXOXVQU2NyY0dGeWRITXNKeTB0YW05aUxXNWhiV1U5Y0hKbFkybHdYM0l4Tmw5elkyaGxaSFZzWlY5dmJteDVKeXduTFMxM2NtRndQWFJ5ZFdVblhYMEtjbVZ6ZFd4MFBYc25ZMmhsWTJ0bFpGOTFkR01uT21SaGRHVjBhVzFsTG5WMFkyNXZkeWdwTG1semIyWnZjbTFoZENncEt5ZGFKeXduYzNWaWJXbDBkR1ZrWDJwdlluTW5PakFzSjIxdlpHVnNYMk5oYkd4ekp6b3dmUXBtYjNJZ2JtRnRaU3hqYjIxdFlXNWtJR2x1SUdOdmJXMWhibVJ6TG1sMFpXMXpLQ2s2Q2lCMGNuazZDaUFnY0QxemRXSndjbTlqWlhOekxuSjFiaWhqYjIxdFlXNWtMSE4wWkc5MWREMXpkV0p3Y205alpYTnpMbEJKVUVVc2MzUmtaWEp5UFhOMVluQnliMk5sYzNNdVVFbFFSU3gxYm1sMlpYSnpZV3hmYm1WM2JHbHVaWE05VkhKMVpTeDBhVzFsYjNWMFBUTXdLUW9nSUhKbGMzVnNkRnR1WVcxbFhUMTdKMlY0YVhSZlkyOWtaU2M2Y0M1eVpYUjFjbTVqYjJSbExDZHpkR1J2ZFhRbk9uQXVjM1JrYjNWMFd6bzFNREF3TUYwc0ozTjBaR1Z5Y2ljNmNDNXpkR1JsY25KYk9qUXdNREJkZlFvZ1pYaGpaWEIwSUhOMVluQnliMk5sYzNNdVZHbHRaVzkxZEVWNGNHbHlaV1E2Y21WemRXeDBXMjVoYldWZFBYc25jM1JoZEdVbk9pZFVTVTFGVDFWVUozMEthRzl0WlQxUVlYUm9LQ2N2WkdGMFlURXZhRzl0WlM5emRXNTVhWEVuS1FweVpYTjFiSFJiSjJWNGFYTjBhVzVuWDNCeVpXTnBjRjl5YjI5MGN5ZGRQVnR6ZEhJb2NDa2dabTl5SUhBZ2FXNGdhRzl0WlM1cGRHVnlaR2x5S0NrZ2FXWWdjQzV1WVcxbExuTjBZWEowYzNkcGRHZ29KM0J5WldOcGNDY3BJR0Z1WkNCd0xtbHpYMlJwY2lncFhWczZNekJkQ25KbGMzVnNkRnNuY21Wd2IzTnBkRzl5ZVY5bGVHbHpkSE1uWFQwb2FHOXRaUzhuYm1WMWNtRnNhSGxrY205c2IyZDVKeWt1YVhOZlpHbHlLQ2tLY21WemRXeDBXeWR3ZVhSb2IyNWZaVzUyYVhKdmJtMWxiblJmYldWMFlXUmhkR0VuWFQxYlhRcGxiblk5YUc5dFpTOG5iV2x1YVdOdmJtUmhNeTlsYm5aekwyNW9YMlpwYm1Gc0p3cG1iM0lnY0dGMGRHVnliaUJwYmlBb0oyeHBZaTl3ZVhSb2IyNHFMM05wZEdVdGNHRmphMkZuWlhNdmRHOXlZMmd2ZG1WeWMybHZiaTV3ZVNjc0oyeHBZaTl3ZVhSb2IyNHFMM05wZEdVdGNHRmphMkZuWlhNdmJuVnRjSGt2ZG1WeWMybHZiaTV3ZVNjcE9nb2dabTl5SUhBZ2FXNGdaVzUyTG1kc2IySW9jR0YwZEdWeWJpazZDaUFnY21WemRXeDBXeWR3ZVhSb2IyNWZaVzUyYVhKdmJtMWxiblJmYldWMFlXUmhkR0VuWFM1aGNIQmxibVFvZXlkd1lYUm9KenB6ZEhJb2NDa3NKM1JsZUhRbk9uQXVjbVZoWkY5MFpYaDBLQ2xiT2pFMk1EQmRmU2tLY0hKcGJuUW9hbk52Ymk1a2RXMXdjeWh5WlhOMWJIUXBLUXBRV1FvPSIsCiAgImNvbW1hbmRfc2hhMjU2IjogIjg5MzI2YjNjN2I5MGFkOWFhNTk2NThiZTEwNmM2ZWY4YmZhMmE0NmNlZjFlMTg2ODcwYWRiNmZlY2NkNWYwNmMiLAogICJwYXlsb2FkX3BhdGgiOiBudWxsLAogICJwYXlsb2FkX3NoYTI1NiI6IG51bGwsCiAgInByb2plY3RfaWQiOiAicHJlY2lwLXIxNi1yZXNvdXJjZS1zdGF0dXMtMjAyNjExMDUiLAogICJwcm90ZWN0ZWRfcmVtb3RlX3Jvb3RzIjogWwogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDIiLAogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMiCiAgXSwKICAicHJvdG9jb2wiOiAiY29uZmlndXJhYmxlLWhwYy1tYWlsYm94LXYxIiwKICAicmVtb3RlX3B5dGhvbiI6ICJweXRob24zIiwKICAicmVtb3RlX3Jvb3QiOiAiL2RhdGExL2hvbWUvc3VueWlxL2hwY19wcm9qZWN0cy9wcmVjaXBfcjE2X3Jlc291cmNlX3N0YXR1c18yMDI2MTEwNSIsCiAgInJlcXVlc3RfaWQiOiAicmVzb3VyY2UtYWxsZ3B1LTIwMjYxMTA1LTE4MjctdjAzIiwKICAic2VxdWVuY2UiOiAzCn0K'))
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
