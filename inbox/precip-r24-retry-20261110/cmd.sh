#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInByZWNpcC1yMjQtcmV0cnktMjAyNjExMTAiLAogICJjb21tYW5kX2Jhc2U2NCI6ICJJeUV2ZFhOeUwySnBiaTlsYm5ZZ1ltRnphQXB6WlhRZ0xXVUtjSGwwYUc5dU15QXRJRHc4SjFCWkp3cG1jbTl0SUdSaGRHVjBhVzFsSUdsdGNHOXlkQ0JrWVhSbGRHbHRaUXBwYlhCdmNuUWdhbk52YmdwbWNtOXRJSEJoZEdoc2FXSWdhVzF3YjNKMElGQmhkR2dLYVcxd2IzSjBJSEpsQ21sdGNHOXlkQ0J6ZFdKd2NtOWpaWE56Q25KdmIzUTlKeTkxYzNJdmJHOWpZV3d2WjJ4dllteGxMM052Wm5SekwzTnNkWEp0THpFNUxqQTFMalF1TVM5aWFXNHZKd3B3WVhKMGN6MG5hR2R3ZFRRc2FHZHdkVEp3TEdobmNIVXlMR2huY0hVNEp3cGpiMjF0WVc1a2N6MTdDaUFuWjNCMVgyNXZaR1Z6SnpwYmNtOXZkQ3NuYzJsdVptOG5MQ2N0VGljc0p5MW9KeXduTFhBbkxIQmhjblJ6TENjdGJ5Y3NKeVZRZkNWT2ZDVjBmQ1ZIZkNWREoxMHNDaUFuWjNCMVgzVnpZV2RsSnpwYmNtOXZkQ3NuYzJsdVptOG5MQ2N0VGljc0p5MXdKeXh3WVhKMGN5d25MVThuTENkdWIyUmxiR2x6ZERveE5DeG5jbVZ6T2pJd0xHZHlaWE4xYzJWa09qTXlMR053ZFhOemRHRjBaVG95TkNkZExBb2dKMkZzYkY5bmNIVmZjM1JoY25SZlpYTjBhVzFoZEdVbk9sdHliMjkwS3lkelltRjBZMmduTENjdExYUmxjM1F0YjI1c2VTY3NKeTB0Ym05a1pYTTlNU2NzSnkwdGJuUmhjMnR6UFRFbkxDY3RMV053ZFhNdGNHVnlMWFJoYzJzOU1pY3NDaUFnSUNBZ0p5MHRaM0psY3oxbmNIVTZNU2NzSnkwdGRHbHRaVDB3Tmpvd01Eb3dNQ2NzSnkwdGNHRnlkR2wwYVc5dVBTY3JjR0Z5ZEhNc0p5MHRhbTlpTFc1aGJXVTljSEpsWTJsd1gzSXlORjl6WTJobFpIVnNaVjl2Ym14NUp5d25MUzEzY21Gd1BYUnlkV1VuWFgwS2NtVnpkV3gwUFhzblkyaGxZMnRsWkY5MWRHTW5PbVJoZEdWMGFXMWxMblYwWTI1dmR5Z3BMbWx6YjJadmNtMWhkQ2dwS3lkYUp5d25jM1ZpYldsMGRHVmtYMnB2WW5Nbk9qQXNKMjF2WkdWc1gyTmhiR3h6Snpvd2ZRcG1iM0lnYm1GdFpTeGpiMjF0WVc1a0lHbHVJR052YlcxaGJtUnpMbWwwWlcxektDazZDaUIwY25rNkNpQWdjRDF6ZFdKd2NtOWpaWE56TG5KMWJpaGpiMjF0WVc1a0xITjBaRzkxZEQxemRXSndjbTlqWlhOekxsQkpVRVVzYzNSa1pYSnlQWE4xWW5CeWIyTmxjM011VUVsUVJTeDFibWwyWlhKellXeGZibVYzYkdsdVpYTTlWSEoxWlN4MGFXMWxiM1YwUFRNd0tRb2dJSEpsYzNWc2RGdHVZVzFsWFQxN0oyVjRhWFJmWTI5a1pTYzZjQzV5WlhSMWNtNWpiMlJsTENkemRHUnZkWFFuT25BdWMzUmtiM1YwV3pvMU1EQXdNRjBzSjNOMFpHVnljaWM2Y0M1emRHUmxjbkpiT2pRd01EQmRmUW9nWlhoalpYQjBJSE4xWW5CeWIyTmxjM011VkdsdFpXOTFkRVY0Y0dseVpXUTZjbVZ6ZFd4MFcyNWhiV1ZkUFhzbmMzUmhkR1VuT2lkVVNVMUZUMVZVSjMwS2FHOXRaVDFRWVhSb0tDY3ZaR0YwWVRFdmFHOXRaUzl6ZFc1NWFYRW5LUXB5WlhOMWJIUmJKMlY0YVhOMGFXNW5YM0J5WldOcGNGOXliMjkwY3lkZFBWdHpkSElvY0NrZ1ptOXlJSEFnYVc0Z2FHOXRaUzVwZEdWeVpHbHlLQ2tnYVdZZ2NDNXVZVzFsTG5OMFlYSjBjM2RwZEdnb0ozQnlaV05wY0NjcElHRnVaQ0J3TG1selgyUnBjaWdwWFZzNk16QmRDbkpsYzNWc2RGc25jbVZ3YjNOcGRHOXllVjlsZUdsemRITW5YVDBvYUc5dFpTOG5ibVYxY21Gc2FIbGtjbTlzYjJkNUp5a3VhWE5mWkdseUtDa0tjbVZ6ZFd4MFd5ZHdlWFJvYjI1ZlpXNTJhWEp2Ym0xbGJuUmZiV1YwWVdSaGRHRW5YVDFiWFFwbGJuWTlhRzl0WlM4bmJXbHVhV052Ym1SaE15OWxiblp6TDI1b1gyWnBibUZzSndwbWIzSWdjR0YwZEdWeWJpQnBiaUFvSjJ4cFlpOXdlWFJvYjI0cUwzTnBkR1V0Y0dGamEyRm5aWE12ZEc5eVkyZ3ZkbVZ5YzJsdmJpNXdlU2NzSjJ4cFlpOXdlWFJvYjI0cUwzTnBkR1V0Y0dGamEyRm5aWE12Ym5WdGNIa3ZkbVZ5YzJsdmJpNXdlU2NwT2dvZ1ptOXlJSEFnYVc0Z1pXNTJMbWRzYjJJb2NHRjBkR1Z5YmlrNkNpQWdjbVZ6ZFd4MFd5ZHdlWFJvYjI1ZlpXNTJhWEp2Ym0xbGJuUmZiV1YwWVdSaGRHRW5YUzVoY0hCbGJtUW9leWR3WVhSb0p6cHpkSElvY0Nrc0ozUmxlSFFuT25BdWNtVmhaRjkwWlhoMEtDbGJPakUyTURCZGZTa0tjSEpwYm5Rb2FuTnZiaTVrZFcxd2N5aHlaWE4xYkhRcEtRcFFXUW89IiwKICAiY29tbWFuZF9zaGEyNTYiOiAiNTZmYmMzNmU1MDcxZTM5N2U3ZDUwZDY3MDBjOWU1MTljZGRjNTU4ZWY4OGI0YTQ2YjUxNzZlNzgwOTkyZDQ2NyIsCiAgInBheWxvYWRfcGF0aCI6IG51bGwsCiAgInBheWxvYWRfc2hhMjU2IjogbnVsbCwKICAicHJvamVjdF9pZCI6ICJwcmVjaXAtcjI0LXJldHJ5LTIwMjYxMTEwIiwKICAicHJvdGVjdGVkX3JlbW90ZV9yb290cyI6IFsKICAgICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fMjAyNjEwMDZfMDAyIiwKICAgICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fZml4ZWQyMDBfMjAyNjEwMTlfMDAzIgogIF0sCiAgInByb3RvY29sIjogImNvbmZpZ3VyYWJsZS1ocGMtbWFpbGJveC12MSIsCiAgInJlbW90ZV9weXRob24iOiAicHl0aG9uMyIsCiAgInJlbW90ZV9yb290IjogIi9kYXRhMS9ob21lL3N1bnlpcS9ocGNfcHJvamVjdHMvcHJlY2lwX3IyNF9yZXRyeV8yMDI2MTExMCIsCiAgInJlcXVlc3RfaWQiOiAicmVzb3VyY2UtcjI0LTIwMjYxMTEwLXYwMSIsCiAgInNlcXVlbmNlIjogMQp9Cg=='))
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
