#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInpoZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFvaklGSmxZV1F0YjI1c2VTQnBiblpsYm5SdmNua2diMllnZEdobElHWnliM3BsYmlCeVpXMXZkbUZzTFdWNGNHVnlhVzFsYm5RZ2NtOXZkSE11SUZkeWFYUmxjeUJ1YjNSb2FXNW5JRzkxZEhOcFpHVWdkR2hsSUhKbGNYVmxjM1FnWkdseVpXTjBiM0o1TGdwelpYUWdMWFVLVWowdlpHRjBZVEV2YUc5dFpTOXpkVzU1YVhFdmVtaGxibXBwWVc1blgyOTVkbDkyTVFwbFkyaHZJQ0lqSXlCa1lYUmxJanNnWkdGMFpRcGxZMmh2SUNJakl5QnliMjkwSUd4cGMzUnBibWNpT3lCc2N5QXRiR0VnSWlSU0lpQXlQaVl4SUh3Z2FHVmhaQ0F0TnpBS1ptOXlJR1FnYVc0Z2RHRnphM01nYkdGa1pHVnlYM1JoYzJ0eklHNDBYM1JoYzJ0ek95Qmtid29nSUdWamFHOGdJaU1qSUNSa0lIUmhjMnN0WkdseUlHTnZkVzUwSWpzZ2JITWdJaVJTTHlSa0lpQXlQaTlrWlhZdmJuVnNiQ0I4SUhkaklDMXNDbVJ2Ym1VS1ptOXlJR1FnYVc0Z2JHRmtaR1Z5WDNSaGMydHpJRzQwWDNSaGMydHpPeUJrYndvZ0lHWnBjbk4wUFNRb2JITWdJaVJTTHlSa0lpQXlQaTlrWlhZdmJuVnNiQ0I4SUdobFlXUWdMVEVwQ2lBZ1pXTm9ieUFpSXlNZ0pHUWdjMkZ0Y0d4bE9pQWtabWx5YzNRaU95QnNjeUF0YkdFZ0lpUlNMeVJrTHlSbWFYSnpkQ0lnTWo0bU1Rb2dJR1ZqYUc4Z0lpTWpJRzV3ZWlCdFpXMWlaWEp6SWpzZ2RXNTZhWEFnTFd3Z0lpUlNMeVJrTHlSbWFYSnpkQzkwWlhOMFgzQnlaV1JwWTNScGIyNXpMbTV3ZWlJZ01qNG1NU0I4SUhSaGFXd2dMVEV5Q21SdmJtVUtaV05vYnlBaUl5TWdZWEowYVdaaFkzUWdZMjl0Y0d4bGRHVnVaWE56SUNobWFXeGxjeUJ3WlhJZ1pHbHlMQ0J6WVcxd2JHVWdiMllnTkRBZ2NHVnlJSEp2YjNRcElncG1iM0lnWkNCcGJpQjBZWE5yY3lCc1lXUmtaWEpmZEdGemEzTWdialJmZEdGemEzTTdJR1J2Q2lBZ2JITWdJaVJTTHlSa0lpQXlQaTlrWlhZdmJuVnNiQ0I4SUhOb2RXWWdMVzRnTkRBZ0xTMXlZVzVrYjIwdGMyOTFjbU5sUFR3b2VXVnpLU0I4SUhkb2FXeGxJSEpsWVdRZ2REc2daRzhnYkhNZ0lpUlNMeVJrTHlSMElpQjhJSGRqSUMxc095QmtiMjVsSUh3Z2MyOXlkQ0I4SUhWdWFYRWdMV01LWkc5dVpRcGxZMmh2SUNJakl5QmthWE5ySWpzZ1pHWWdMV2dnTDJSaGRHRXhMMmh2YldVdmMzVnVlV2x4SURJK0pqRWdmQ0IwWVdsc0lDMHlDbVZqYUc4Z0lpTWpJR2x0Y0dGamRDQnliMjkwY3lJN0lHeHpJQzFzWVNBaUpGSWlMMjQwWDJsdGNHRmpkQ0FpSkZJaUwyeGhaR1JsY2w5cGJYQmhZM1FnTWo0bU1TQjhJR2hsWVdRZ0xUTXdDbVZqYUc4Z0lpTWpJSE5zZFhKdElITnVZWEJ6YUc5MElqc2dMM1Z6Y2k5c2IyTmhiQzluYkc5aWJHVXZjMjltZEhNdmMyeDFjbTB2TVRrdU1EVXVOQzR4TDJKcGJpOXphVzVtYnlBdGJ5QWlKVkFnSldFZ0pVUWdKWFFnSlVjaUlESStKakVnZkNCb1pXRmtJQzB6TUFwbFkyaHZJQ0lqSXlCQlVsUkpSa0ZEVkY5Q1JVZEpUaUlLZEdGeUlHTjZaaUF0SUMxRElDSWtVaTl1TkY5cGJYQmhZM1FpSUc0MFgzUmhjMnRmWlhKeWIzSnpMbU56ZGlCdU5GOW1iMnhrWDJOdmMzUnpMbU56ZGlBeVBpOWtaWFl2Ym5Wc2JDQjhJR0poYzJVMk5DQXRkeUF3Q21WamFHOEtaV05vYnlBaUl5TWdRVkpVU1VaQlExUmZSVTVFSWdvPSIsCiAgImNvbW1hbmRfc2hhMjU2IjogIjUzNTQ1NTY3NTAzNmQxZWNkNjhjM2ZmMGIyODUyZDZhM2JiMWQ0MDNlMGM2MzkzM2ZiNzQ4ZTg5Y2FiZjQ0NTciLAogICJwYXlsb2FkX3BhdGgiOiBudWxsLAogICJwYXlsb2FkX3NoYTI1NiI6IG51bGwsCiAgInByb2plY3RfaWQiOiAiemhlbmppYW5nLWpocnMtcmV2aXNpb24iLAogICJwcm90ZWN0ZWRfcmVtb3RlX3Jvb3RzIjogWwogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDIiLAogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMiCiAgXSwKICAicHJvdG9jb2wiOiAiY29uZmlndXJhYmxlLWhwYy1tYWlsYm94LXYxIiwKICAicmVtb3RlX3B5dGhvbiI6ICJweXRob24zIiwKICAicmVtb3RlX3Jvb3QiOiAiL2RhdGExL2hvbWUvc3VueWlxL2hwY19wcm9qZWN0cy96aGVuamlhbmctamhycy1yZXZpc2lvbiIsCiAgInJlcXVlc3RfaWQiOiAiaW52ZW50b3J5LTAwMSIsCiAgInNlcXVlbmNlIjogMQp9Cg=='))
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
