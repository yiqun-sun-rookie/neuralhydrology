#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInpoZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFvaklGSmxZV1F0YjI1c2VTQndiR0Z1Ym1sdVp5QnpibUZ3YzJodmRDNGdVM1ZpYldsMGN5QnViM1JvYVc1bk9pQnpZbUYwWTJnZ2FYTWdiMjVzZVNCallXeHNaV1FnZDJsMGFDQXRMWFJsYzNRdGIyNXNlUzRLYzJWMElDMTFDbE5NUFM5MWMzSXZiRzlqWVd3dloyeHZZbXhsTDNOdlpuUnpMM05zZFhKdEx6RTVMakExTGpRdU1TOWlhVzRLVWowdlpHRjBZVEV2YUc5dFpTOXpkVzU1YVhFdmVtaGxibXBwWVc1blgyOTVkbDkyTVFwbFkyaHZJQ0lqSXlCa1lYUmxJanNnWkdGMFpRcGxZMmh2SUNJakl5QndZWEowYVhScGIyNXpJanNnSkZOTUwzTnBibVp2SUMxdklDSWxVQ0FsWVNBbFJDQWxkQ0FsUnlJZ01qNG1NU0I4SUdkeVpYQWdMVVVnSWxCQlVsUkpWRWxQVG54b1ozQjFJaUI4SUdobFlXUWdMVE13Q21WamFHOGdJaU1qSUc5M2JpQnhkV1YxWlNCaWVTQndZWEowYVhScGIyNGdZVzVrSUhOMFlYUmxJZ29rVTB3dmMzRjFaWFZsSUMxMUlDSWtWVk5GVWlJZ0xXZ2dMVzhnSWlWUUlDVlVJaUF5UGlZeElId2djMjl5ZENCOElIVnVhWEVnTFdNS1pXTm9ieUFpSXlNZ1pYTjBhVzFoZEdWa0lITjBZWEowTENCdWIzUm9hVzVuSUhOMVltMXBkSFJsWkNJS1ptOXlJSEFnYVc0Z2FHZHdkVGdnYUdkd2RUSndJR2huY0hVeU95Qmtid29nSUdWamFHOGdJaTB0SUNSd0lnb2dJSFJwYldWdmRYUWdNakFnSkZOTUwzTmlZWFJqYUNBdExYUmxjM1F0YjI1c2VTQXRjQ0FpSkhBaUlDMU9JREVnTFc0Z01TQXRMV053ZFhNdGNHVnlMWFJoYzJzOU5DQXRMV2R5WlhNOVozQjFPakVnTFhRZ01EQTZOVEE2TURBZ0xTMTNjbUZ3UFhSeWRXVWdNajRtTVNCOElIUmhhV3dnTFRFS1pHOXVaUXBsWTJodklDSWpJeUJ1TkNCaGNuSmhlU0JsYkdGd2MyVmtJSE5sWTI5dVpITWdiMjRnUVRnd01DSUtKRk5NTDNOaFkyTjBJQzFxSURJeE16VTVPQ3d5TVRNMU9Ua2dMVmdnTFc0Z0xWQWdMUzFtYjNKdFlYUTlSV3hoY0hObFpDeFRkR0YwWlNBeVBpOWtaWFl2Ym5Wc2JDQjhJR0YzYXlBdFJpZGJmRHBkSnlBbkpEUTlQU0pEVDAxUVRFVlVSVVFpZTNNOUpERXFNell3TUNza01pbzJNQ3NrTXp0dUt5czdkQ3M5Y3p0cFppaHpQbTBwYlQxemZVVk9SSHRwWmlodUtYQnlhVzUwWmlBaWJqMGxaQ0J0WldGdVBTVXVNV1lnYldGNFBTVmtYRzRpTEc0c2RDOXVMRzE5Sndva1Uwd3ZjMkZqWTNRZ0xXb2dNakV6TlRrNExESXhNelU1T1NBdFdDQXRiaUF0VUNBdExXWnZjbTFoZEQxVGRHRnlkQ3hGYm1Rc1UzUmhkR1VnTWo0dlpHVjJMMjUxYkd3Z2ZDQmhkMnNnTFVZbmZDY2dKeVF6UFQwaVEwOU5VRXhGVkVWRUludHBaaWhoUFQwaUlueDhKREU4WVNsaFBTUXhPMmxtS0NReVBtSXBZajBrTW4xRlRrUjdjSEpwYm5RZ0ltWnBjbk4wWDNOMFlYSjBJaXhoTENKc1lYTjBYMlZ1WkNJc1luMG5DbVZqYUc4Z0lpTWpJSE5oYlhCc1pXUWdjblZ1SUdsa1pXNTBhWFJwWlhNaUNuQjVkR2h2YmpNZ0xTQThQQ2RRV1NjS2FXMXdiM0owSUdwemIyNHNJRzl6TENCemRHRjBhWE4wYVdOeklHRnpJSE4wQ2xJOUlpOWtZWFJoTVM5b2IyMWxMM04xYm5scGNTOTZhR1Z1YW1saGJtZGZiM2wyWDNZeElncG1iM0lnWkNCcGJpQW9JblJoYzJ0eklpd2liR0ZrWkdWeVgzUmhjMnR6SWl3aWJqUmZkR0Z6YTNNaUtUb0tJQ0FnSUc1aGJXVnpQWE52Y25SbFpDaHZjeTVzYVhOMFpHbHlLRzl6TG5CaGRHZ3VhbTlwYmloU0xHUXBLU2tLSUNBZ0lIQnBZMnM5Ym1GdFpYTmJPanB0WVhnb01TeHNaVzRvYm1GdFpYTXBMeTgwTUNsZENpQWdJQ0JsYkQxYlhUdGxjRDFiWFR0bmNIVTllMzBLSUNBZ0lHWnZjaUJ1SUdsdUlIQnBZMnM2Q2lBZ0lDQWdJQ0FnZEhKNU9nb2dJQ0FnSUNBZ0lDQWdJQ0JxUFdwemIyNHViRzloWkNodmNHVnVLRzl6TG5CaGRHZ3VhbTlwYmloU0xHUXNiaXdpY25WdVgybGtaVzUwYVhSNUxtcHpiMjRpS1NrcENpQWdJQ0FnSUNBZ1pYaGpaWEIwSUVWNFkyVndkR2x2YmpvS0lDQWdJQ0FnSUNBZ0lDQWdZMjl1ZEdsdWRXVUtJQ0FnSUNBZ0lDQmxiQzVoY0hCbGJtUW9haTVuWlhRb0ltVnNZWEJ6WldSZmMyVmpiMjVrY3lJc01DNHdLU2s3SUdWd0xtRndjR1Z1WkNocUxtZGxkQ2dpWTI5dGNHeGxkR1ZrWDJWd2IyTm9jeUlzTUNrcENpQWdJQ0FnSUNBZ1p6MXFMbWRsZENnaWNuVnVkR2x0WlY5bGJuWnBjbTl1YldWdWRDSXNlMzBwTG1kbGRDZ2laM0poY0docFkzTmZjSEp2WTJWemMyOXlYMjVoYldVaUxDSS9JaWs3SUdkd2RWdG5YVDFuY0hVdVoyVjBLR2NzTUNrck1Rb2dJQ0FnY0hKcGJuUW9aQ3hzWlc0b2JtRnRaWE1wTENKellXMXdiR1ZrSWl4c1pXNG9aV3dwTENKdFpXUnBZVzVmY3lJc2NtOTFibVFvYzNRdWJXVmthV0Z1S0dWc0tTd3hLU3dpYldGNFgzTWlMSEp2ZFc1a0tHMWhlQ2hsYkNrc01Ta3NJbTFsWkdsaGJsOWxjRzlqYUhNaUxITjBMbTFsWkdsaGJpaGxjQ2tzWjNCMUtRcFFXUXBsWTJodklDSWpJeUJ3YkdGMFptOXliU0JqYjI1MGNtOXNJanNnYkhNZ0lpUlNMM0JzWVhSbWIzSnRYMk52Ym5SeWIyeGZZVGd3TUNJZ01qNHZaR1YyTDI1MWJHd2dmQ0IzWXlBdGJBcGxZMmh2SUNJakl5QmpiMlJsSUdGdVpDQnBibkIxZEhNaUNteHpJQzFrSUNJa1VpOXlaWEJ2TDNOamNtbHdkSE12Ylc5a1pXeHBibWNpSUNJa1VpOXdlWE5wZEdVaUlESStKakVLYkhNZ0lpUlNMM0psY0c4dlpHRjBZUzl3Y205alpYTnpaV1FpSURJK0pqRWdmQ0JvWldGa0lDMDFDbWRwZENBdFF5QWlKRkl2Y21Wd2J5SWdiRzluSUMwdGIyNWxiR2x1WlNBdE1TQXlQaVl4SUh3Z2FHVmhaQ0F0TVFwbFkyaHZJQ0lqSXlCbGJuWnBjbTl1YldWdWRDSUtjMjkxY21ObElDOWtZWFJoTVM5b2IyMWxMeVI3VlZORlVuMHZiV2x1YVdOdmJtUmhNeTlsZEdNdmNISnZabWxzWlM1a0wyTnZibVJoTG5Ob0lESStMMlJsZGk5dWRXeHNJQ1ltSUdOdmJtUmhJR0ZqZEdsMllYUmxJRzVvWDJacGJtRnNJREkrTDJSbGRpOXVkV3hzSUNZbUlIQjVkR2h2YmlBdFl5QWlhVzF3YjNKMElITjVjeXh1ZFcxd2VUdHdjbWx1ZENoemVYTXVkbVZ5YzJsdmJpNXpjR3hwZENncFd6QmRMRzUxYlhCNUxsOWZkbVZ5YzJsdmJsOWZLU0lnTWo0bU1TQjhJR2hsWVdRZ0xUSUtjSGwwYUc5dUlDMWpJQ0pwYlhCdmNuUWdkRzl5WTJnN2NISnBiblFvZEc5eVkyZ3VYMTkyWlhKemFXOXVYMThwSWlBeVBpWXhJSHdnZEdGcGJDQXRNUXBsWTJodklDSWpJeUJrYVhOcklqc2daR1lnTFdnZ0wyUmhkR0V4TDJodmJXVXZjM1Z1ZVdseElESStKakVnZkNCMFlXbHNJQzB4Q21SMUlDMXphQ0FpSkZJdmJqUmZkR0Z6YTNNaUlESStMMlJsZGk5dWRXeHNJSHdnZEdGcGJDQXRNUW89IiwKICAiY29tbWFuZF9zaGEyNTYiOiAiMzQ4NTU2ZTZmZDE0OTVhOGM2NDA1NzFiMzg0MTJmNGM1ODkzMzhiYTNhODJmOTgyMzk0ZmM3MGNhNGMxYzk0ZSIsCiAgInBheWxvYWRfcGF0aCI6IG51bGwsCiAgInBheWxvYWRfc2hhMjU2IjogbnVsbCwKICAicHJvamVjdF9pZCI6ICJ6aGVuamlhbmctamhycy1yZXZpc2lvbiIsCiAgInByb3RlY3RlZF9yZW1vdGVfcm9vdHMiOiBbCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uXzIwMjYxMDA2XzAwMiIsCiAgICAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uX2ZpeGVkMjAwXzIwMjYxMDE5XzAwMyIKICBdLAogICJwcm90b2NvbCI6ICJjb25maWd1cmFibGUtaHBjLW1haWxib3gtdjEiLAogICJyZW1vdGVfcHl0aG9uIjogInB5dGhvbjMiLAogICJyZW1vdGVfcm9vdCI6ICIvZGF0YTEvaG9tZS9zdW55aXEvaHBjX3Byb2plY3RzL3poZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAicmVxdWVzdF9pZCI6ICJyZXNvdXJjZXMtMDAxIiwKICAic2VxdWVuY2UiOiAyCn0K'))
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
