#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInpoZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFvaklFUmxjR3h2ZVNCSU1TQm1iM0lnZDJodmJHVWdjMlZsWkhNZ2IyNXNlU3dnYjI0Z1QwNUZJSEJoY25ScGRHbHZiaXdnYzIxdmEyVWdabWx5YzNRc0lHRnljbUY1SUdGbWRHVnlMZ29qSUZObFpXUWdZbXh2WTJ0eklHbHVJSFJoYzJzZ2IzSmtaWEk2SURFM09qQXRPVFVnTWprNk9UWXRNVGt4SURRek9qRTVNaTB5T0RjZ05UYzZNamc0TFRNNE15QTNNVG96T0RRdE5EYzVJRGd6T2pRNE1DMDFOelVnT1RjNk5UYzJMVFkzTVNBeE1EazZOamN5TFRjMk55QXhNamM2TnpZNExUZzJNeUF4TXprNk9EWTBMVGsxT1FvaklGQmhlV3h2WVdRNklIQmhlV3h2WVdSekwycG9jbk5mYURGZmNHRjViRzloWkY5Mk1TNTBZWEl1WjNvZ0tIUm9aU0J0WVdsc1ltOTRJR1Y0ZEhKaFkzUnpJR2wwSUdsdWRHOGdKRWhRUTE5UVFWbE1UMEZFWDBSSlVpa3VDaU1nUW1WbWIzSmxJSEIxWW14cGMyaHBibWNnY21Wd2JHRmpaU0JvWjNCMU9Dd2dOVGMyTFRnMk15VXhOaUFvZEdGemF5MXBibVJsZUNCeVlXNW5aWE1nYjJZZ2QyaHZiR1VnYzJWbFpITWdjR3gxY3lBbE1UWXBJR0Z1WkNBMU56WWdLRzl1WlNCcGJtUmxlQ0JtY205dElIUm9iM05sSUhKaGJtZGxjeWt1Q25ObGRDQXRaWFVLVUVGU1ZEMW9aM0IxT0FwVFREMHZkWE55TDJ4dlkyRnNMMmRzYjJKc1pTOXpiMlowY3k5emJIVnliUzh4T1M0d05TNDBMakV2WW1sdUNsSlBUMVE5SWlSSVVFTmZVRkpQU2tWRFZGOVNUMDlVTDJneFgzWXhJZ3BwWmlCYklDMWxJQ0lrVWs5UFZDOW9NVjkwWVhOcmN5SWdYVHNnZEdobGJpQmxZMmh2SUNKU1QwOVVYMEZNVWtWQlJGbGZTRUZUWDFSQlUwdFRPaUFrVWs5UFZDSTdJR1Y0YVhRZ01Uc2dabWtLYld0a2FYSWdMWEFnSWlSU1QwOVVJZ3BqY0NBdGNpQWlKRWhRUTE5UVFWbE1UMEZFWDBSSlVpSXZMaUFpSkZKUFQxUWlMd3BqWkNBaUpGSlBUMVFpQ25CNWRHaHZiak1nTFNBOFBDZFFXU2NLYVcxd2IzSjBJR2hoYzJoc2FXSXNJR3B6YjI0c0lITjVjd3B0SUQwZ2FuTnZiaTVzYjJGa0tHOXdaVzRvSWsxQlRrbEdSVk5VTG1wemIyNGlLU2tLWW1Ga0lEMGdXMnNnWm05eUlHc3NJSFlnYVc0Z2JTNXBkR1Z0Y3lncElHbG1JR2hoYzJoc2FXSXVjMmhoTWpVMktHOXdaVzRvYXl3Z0luSmlJaWt1Y21WaFpDZ3BLUzVvWlhoa2FXZGxjM1FvS1NBaFBTQjJYUXB3Y21sdWRDZ2liV0Z1YVdabGMzUmZabWxzWlhNaUxDQnNaVzRvYlNrc0lDSnRhWE50WVhSamFHVnpJaXdnYkdWdUtHSmhaQ2twQ25ONWN5NWxlR2wwS0RFZ2FXWWdZbUZrSUdWc2MyVWdNQ2tLVUZrS2JXdGthWElnTFhBZ2JHOW5jeUJvTVY5MFlYTnJjeUJ6Ylc5clpWOTBZWE5yY3dwM2NtbDBaVjlxYjJJb0tTQjdDaUFnSXlBa01TQnFiMklnYm1GdFpTd2dKRElnWVhKeVlYa2djM0JsWXl3Z0pETWdiM1YwY0hWMElISnZiM1FzSUNRMElIUmhjMnNnYVc1a1pYZ2daWGh3Y21WemMybHZiZ29nSUdOaGRDQStJQ0lrTVM1emJIVnliU0lnUER4RlQwWUtJeUV2ZFhOeUwySnBiaTlsYm5ZZ1ltRnphQW9qVTBKQlZFTklJQzFLSUNReENpTlRRa0ZVUTBnZ0xYQWdKSHRRUVZKVWZRb2pVMEpCVkVOSUlDMU9JREVLSTFOQ1FWUkRTQ0F0YmlBeENpTlRRa0ZVUTBnZ0xTMWpjSFZ6TFhCbGNpMTBZWE5yUFRRS0kxTkNRVlJEU0NBdExXZHlaWE05WjNCMU9qRUtJMU5DUVZSRFNDQXRMV0Z5Y21GNVBTUXlDaU5UUWtGVVEwZ2dMWFFnTURBNk5UQTZNREFLSTFOQ1FWUkRTQ0F0YnlBa2UxSlBUMVI5TDJ4dlozTXZKREZmSlVGZkpXRXViM1YwQ2lOVFFrRlVRMGdnTFdVZ0pIdFNUMDlVZlM5c2IyZHpMeVF4WHlWQlh5VmhMbVZ5Y2dwelpYUWdMV1Z2SUhCcGNHVm1ZV2xzQ25OdmRYSmpaU0F2WkdGMFlURXZhRzl0WlM5emRXNTVhWEV2YldsdWFXTnZibVJoTXk5bGRHTXZjSEp2Wm1sc1pTNWtMMk52Ym1SaExuTm9DbU52Ym1SaElHRmpkR2wyWVhSbElHNW9YMlpwYm1Gc0NtVjRjRzl5ZENCUVdWUklUMDVRUVZSSVBTOWtZWFJoTVM5b2IyMWxMM04xYm5scGNTOTZhR1Z1YW1saGJtZGZiM2wyWDNZeEwzQjVjMmwwWlRwY0pIdFFXVlJJVDA1UVFWUklPaTE5Q21WNGNHOXlkQ0JQVFZCZlRsVk5YMVJJVWtWQlJGTTlOQ0JOUzB4ZlRsVk5YMVJJVWtWQlJGTTlOQXB1ZG1sa2FXRXRjMjFwSUMwdGNYVmxjbmt0WjNCMVBXNWhiV1VnTFMxbWIzSnRZWFE5WTNOMkxHNXZhR1ZoWkdWeUlIeDhJSFJ5ZFdVS1kyUWdKSHRTVDA5VWZRcHdlWFJvYjI0Z0xYVWdMVmdnZFhSbU9DQXRRaUJ6WTNKcGNIUnpMMjF2WkdWc2FXNW5MM3BvWlc1cWFXRnVaMTlxYUhKelgzUnBaR1ZmWTI5dWRISnZiRjkwY21GcGJtbHVaeTV3ZVNBdExYUmhjMnN0YVc1a1pYZ2dKRFFnTFMxdmRYUndkWFF0Y205dmRDQWtNd3BGVDBZS2ZRcDNjbWwwWlY5cWIySWdhbWh5YzE5b01WOXpiVzlyWlNBaU5UYzJMVFUzTmlJZ0lpUjdVazlQVkgwdmMyMXZhMlZmZEdGemEzTWlJQ0kxTnpZaUNuZHlhWFJsWDJwdllpQnFhSEp6WDJneElDSTFOell0T0RZekpURTJJaUFpSkh0U1QwOVVmUzlvTVY5MFlYTnJjeUlnSWx3a2UxTk1WVkpOWDBGU1VrRlpYMVJCVTB0ZlNVUjlJZ3BUVFU5TFJUMGtLQ1JUVEM5elltRjBZMmdnTFMxd1lYSnpZV0pzWlNCcWFISnpYMmd4WDNOdGIydGxMbk5zZFhKdEtRcEJVbEpCV1Qwa0tDUlRUQzl6WW1GMFkyZ2dMUzF3WVhKellXSnNaU0F0TFdSbGNHVnVaR1Z1WTNrOVlXWjBaWEp2YXpva2UxTk5UMHRGZlNCcWFISnpYMmd4TG5Oc2RYSnRLUXBsWTJodklDSndZWEowYVhScGIyNDlKSHRRUVZKVWZTQnpiVzlyWlY5cWIySTlKSHRUVFU5TFJYMGdZWEp5WVhsZmFtOWlQU1I3UVZKU1FWbDlJSEp2YjNROUpIdFNUMDlVZlNJS0pGTk1MM054ZFdWMVpTQXRhaUFpSkh0VFRVOUxSWDBzSkh0QlVsSkJXWDBpSUMxb0lDMXZJQ0lsYVNBbFVDQWxWQ0FsVWlJZ01qNG1NU0I4SUdobFlXUWdMVFVLIiwKICAiY29tbWFuZF9zaGEyNTYiOiAiYTkzMjNiNjgwNjk0OWU2MzRjNTA1NGM3YTk2MzJmOGQ1ODZiMjU0MjQ0MjdiZjk0MDBiNzVkNTA0NTc2YTkzOSIsCiAgInBheWxvYWRfcGF0aCI6ICJpbmJveC96aGVuamlhbmctamhycy1yZXZpc2lvbi9wYXlsb2FkXzgudGFyLmd6IiwKICAicGF5bG9hZF9zaGEyNTYiOiAiYzExYWE5ZjYwMDQ5NGM5ZDY5MjU3N2NjYTEwYWVkOTIxYWNlYmMwODBiZTdjNGFhZDg3YTM5YTYyZDZjZjI4MiIsCiAgInByb2plY3RfaWQiOiAiemhlbmppYW5nLWpocnMtcmV2aXNpb24iLAogICJwcm90ZWN0ZWRfcmVtb3RlX3Jvb3RzIjogWwogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDIiLAogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMiCiAgXSwKICAicHJvdG9jb2wiOiAiY29uZmlndXJhYmxlLWhwYy1tYWlsYm94LXYxIiwKICAicmVtb3RlX3B5dGhvbiI6ICJweXRob24zIiwKICAicmVtb3RlX3Jvb3QiOiAiL2RhdGExL2hvbWUvc3VueWlxL2hwY19wcm9qZWN0cy96aGVuamlhbmctamhycy1yZXZpc2lvbiIsCiAgInJlcXVlc3RfaWQiOiAiZGVwbG95LWgxLWhncHU4LTAwMSIsCiAgInNlcXVlbmNlIjogOAp9Cg=='))
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
