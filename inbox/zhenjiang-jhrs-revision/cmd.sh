#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInpoZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFvaklGTjFZbTFwZENCelpXVmtJREV5TnlBb2RHRnpheUJwYm1ScFkyVnpJRGMyT0MwNE5qTXBJRzl1SUdobmNIVTRJSGRwZEdnZ2RHaGxJR1Y0YVhOMGFXNW5JRWd4SUdwdllpQnpZM0pwY0hRZ1lXNWtJRzkxZEhCMWRDQnliMjkwTGdwelpYUWdMV1YxQ2xOTVBTOTFjM0l2Ykc5allXd3ZaMnh2WW14bEwzTnZablJ6TDNOc2RYSnRMekU1TGpBMUxqUXVNUzlpYVc0S1VrOVBWRDBpSkVoUVExOVFVazlLUlVOVVgxSlBUMVF2YURGZmRqRWlDbU5rSUNJa1VrOVBWQ0lLWkdGMFpRcHdjbVZ6Wlc1MFBTUW9iSE1nYURGZmRHRnphM01nTWo0dlpHVjJMMjUxYkd3Z2ZDQm5jbVZ3SUMxaklDZHpaV1ZrWHpFeU55UW5JSHg4SUhSeWRXVXBDbVZqYUc4Z0luTmxaV1FnTVRJM0lIUmhjMnNnWkdseVpXTjBiM0pwWlhNZ2NISmxjMlZ1ZENCaVpXWnZjbVVnYzNWaWJXbDBPaUFrZTNCeVpYTmxiblI5SWdwcFppQmJJQ0lrZTNCeVpYTmxiblI5SWlBaFBTQWlNQ0lnWFRzZ2RHaGxiaUJsWTJodklDSlRSVVZFWHpFeU4xOUJURkpGUVVSWlgxTlVRVkpVUlVSZlNFVlNSU0k3SUdWNGFYUWdNVHNnWm1rS1NrOUNQU1FvSkZOTUwzTmlZWFJqYUNBdExYQmhjbk5oWW14bElDMHRZWEp5WVhrOU56WTRMVGcyTXlVeE5pQnFhSEp6WDJneExuTnNkWEp0S1FwbFkyaHZJQ0p6ZFdKdGFYUjBaV1FnWVhKeVlYazlKSHRLVDBKOUlHbHVaR2xqWlhNZ056WTRMVGcyTXlBb2MyVmxaQ0F4TWpjcElncHpiR1ZsY0NBeU95QWtVMHd2YzNGMVpYVmxJQzExSUNJa1ZWTkZVaUlnTFdnZ0xXNGdhbWh5YzE5b01TQXRieUFpSldrZ0pWUWdKVklpSUh3Z2FHVmhaQ0F0TmdvPSIsCiAgImNvbW1hbmRfc2hhMjU2IjogIjkyNDk3MTk3OGJjODMwYTQ4MDdlYTI4NjNjNDllMjEwYmRkYTBiYmQyZmM2ZDQ3OWIyNWQ2OTdmMTgyMmMzYjYiLAogICJwYXlsb2FkX3BhdGgiOiBudWxsLAogICJwYXlsb2FkX3NoYTI1NiI6IG51bGwsCiAgInByb2plY3RfaWQiOiAiemhlbmppYW5nLWpocnMtcmV2aXNpb24iLAogICJwcm90ZWN0ZWRfcmVtb3RlX3Jvb3RzIjogWwogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDIiLAogICAgIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMiCiAgXSwKICAicHJvdG9jb2wiOiAiY29uZmlndXJhYmxlLWhwYy1tYWlsYm94LXYxIiwKICAicmVtb3RlX3B5dGhvbiI6ICJweXRob24zIiwKICAicmVtb3RlX3Jvb3QiOiAiL2RhdGExL2hvbWUvc3VueWlxL2hwY19wcm9qZWN0cy96aGVuamlhbmctamhycy1yZXZpc2lvbiIsCiAgInJlcXVlc3RfaWQiOiAic3VibWl0LXNlZWQxMjciLAogICJzZXF1ZW5jZSI6IDE4Cn0K'))
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
