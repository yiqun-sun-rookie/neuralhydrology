#!/bin/bash
sequence=150
umask 077
exec 2>/dev/null
openssl version >/dev/null 2>&1 || { printf '%s\n' TRANSPORT_PREREQUISITES_FAILED; exit 1; }
transport_python=''
for candidate in /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -B -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
        transport_python="$candidate"
        break
    fi
done
if [ -z "$transport_python" ]; then printf '%s\n' TRANSPORT_PREREQUISITES_FAILED; exit 1; fi
"$transport_python" -B - <<'TRANSPORT_PY'
Q = {'sequence': 150, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '706e320ec21461095c25c95b961f8e9015d11b97d39642f5079cda09e61e43fa', 'ciphertext': 'MIIJPQYJKoZIhvcNAQcDoIIJLjCCCSoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGATE06pAm9zSy5r/GKxWzHblWsB4jvk0rAJE/mS2+rLKP328MxbSlANg6Wlm56e9kuw2Sg7bc/68e0djaTzM3rWV2sv2l2WQtxcnQH37Mj5T44uL3ua2AUhA3szEraFiAyQP8mxjZSyuNYlt4weBUzw1wVFbBxvz+LKeAVJfsn2/iS8NwtRFXxyKMHwvVeE3cCRrh1Cq6kPSXHBzYMBMvDChj1fE0AVyzFlS6htYR0xe+1WT2U6ZEV9dQIX4S89Y+LWS0i9T7Y4U/wgm+t0tgbLlYwqqEeKCQibf42LMcI2CnXk/O5zjlt24DmbRonNSd5i61D6L/UrYYQIRCcylyJGdm0X11Tezp5YSkCmZWsM3chfDhsTflJwdHhibcE3MfrXaltDn5c3bRoO9w/IyMc7OnRGNVNJjtqyL4GbVDKLp+awVXiOVtfSIKaS7TZk/qrN2A8hgzBonHDqXYCMa6IP42z3ssOxJ2G+GBC0e+k3yxAuzWCnmEBNKONJRDcWIrNMIIHTgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQTarPJGXtXWMZpzjFxgGCOICCByC1Mw7zYOBny2LPZ2Ei7pq7Fj+cqtM4bgPn8pAXMul4CqX8qyThcUanTFeiy7sYND4WtmFo6bbutFUaJqnZFSPW582iDsOU0ij5yH5xVVTnBDyjhfvTc2TeGx+7u2In9cGzaBh5ym1JpvwU3IrPfBrbLg0O6K1htNU2Fx7N1yMFcPJYd+uT8OBPTUMKb9Cg6bxET9m3k4WzTm43EiqgJJQZ3ll3u0SsRC80ybgHofvIIOpwE7wQW+aifpxEYdFC4+YesPT7bnX4PdDDrCC3GTc+n1JrmdP8bDwx9jvb2X9UYlf17NDNRTV5uC/bGqB55o+Pr5Gx2w8HXjWOrW1LGRK8BAkI5MsbfsqgfsfZ2h/va9K4Isoq+iV5Sp+A1BdhJ8odXcFSGCP0y4YJpq61gpqLzJRhDi3tCbhdsceW4xLaaI6xlFvH8A6NVmxjdZKhFDcdgF9pBJVypKtlYvAmVQ8bHTNfsCTDCzRdn83pGfpUQjVi4lsT6V6IIxcS+iwmYsvZbsIr11DGDWH9xliCtVbOwqWz3HOImZcNSunm9QrH9OGMWSUrt0kHqq2bayJtfDe9Zh2BVmfyQPVBxEzRED9dskfhgZHk+U0HXKsagrjhsKz5AGJgkxT9M1TWkEcAfBSAYNfbuBSPoMJ8sdQ05t5w/oAlx9QgPlSYqznoVG6vMViwDZg/5aDteQoL2sPxf+1sTWWG8XqzEdI8TKWlQ1/RihEnTKuh8sxfOJs5d4+puGHyxDe5ShMs4kbHvyqsj3CffZKrLnq88l+sFxhQJ7NwcRlKJCBt8FZc4NwllDn64v4xzVk0c8PvhXVrqgXAEA6Wkq/MbPc7nh4GV7tqO/uRZOC9lrW5cOhqIf5aDqk3SQJJc+dcIvNbg6xDlBweV68GbLUICIpIlMF11s1Teu37jLhNtZXJssc9r1SujNI9uc0lvNOPwxHGqVZEEOrfFyZ5q7uRj+s0K/tfd6OGV71xACfe015jA9StYL/YdpxsYKVTNO6Hub284kTjHjmuRvah82eUy6rCkHhE82idk5KgReaijVwjZtHoYQcfQ64MSfBnrzo9cRggnWjvgkydECa8EKO3VUI+dEu64xwTgCn6FWMYbQa2dZkQBai7rJiHRlh+0/GoK4Ihx9fBJAy63QNCgxKWeg1MYTCdpYzsa2NIvKbeyEmEziLFMn9SsL7FL6diN5l0UngdUFX1oMAIXbignasRFWcsnBrlN2MmSImdFNcci02UdI512BTqFDGdR9yTQRsXytyFfO9NBNg9kZLpaRY3hrEGlX0t0Wx/wf2wjwPxC/3vzsE/5+lF+AzahfMGnHTDXyjFs7XJ6H6q8AwE+SB1/vbJ6maYnUOmX+orBfGAkUkW8ewjVqfETVPo9zwiCzeQeJW3atOuQXKpSErp1u+4rdNdatXhmdT66RSXcibjGYIFOlQ1U1xPV6iOJBbonjJYDSgkB2EqWd7uauXwSE4NLTpaZ1ZkaiXZ+80BBQ3Fh9s3V0JdZhm2/hHPvYr5Z/UZ6F800o4k5mRjzg2KNRHqNrJ8G66+8gfcNAqtyIbfsnZXJZLMju62rBRagRhFGYz26DuWwMcNRpdA1pZrxh+ZDZ0U7XVieLGTNcYjUO5+ApSKzaROU1Vy9J2XLDaSJkypdXI72TLKK05ZqfzXD7ImQaothUyoXQh7bzFYLkFGABmlfjgsw6JdiquiyMCyJltgtdSsGP55riEOqcNoWbejhtrmOt3e9r2ggR96WYMhTEnaboyV7flDV5/pW+wruLaUpA3m8lZNUE+FwuKNhoYvL2F+cSoP6sAcrM4GHTsUFyc7KAeLdoXHKeCHTIkf0vnAPreJhf/n8YnDgKxGLmeeZmrWfLKcUJUolF8NKhZsbAgt6GOemLXd2GbJvQYu2C/+hQn6J5LiAigQ377O7uQamcKDleMAFd6PyG7V+vw/KDFEq3gkpvv6dqqQEGQqUni6azrkLMSWQMu0B0Y6okyqkzckxjIj+3IV9h/CUz2itzhFDtWgHgb1wtkfEn/X3kxIf6fJjh72BmLGrj4G4N4F3/LciXhspAhKQscyQzOns+qqkIm7w/SDyRmpARZyqK6pnTLkDFtR8qWtLP3LV4CZgR54WLZyI7WACJJ+JC0qRCA/s2mbFTiHyaM12r4n4k98mfw0MtNMZ3exQ9Z1DtecDXxmVkkCI2Te4X+8r+cCS8HIXFRQv8/Lqb3oyMDOUgp3+xfEoWJxqS/ZdtQDjdJi5Grq39zPh3lMlgMciMdbXAuzCUaOuxZRI1PnmQ4H8BPQ5GBL0M/E7/UlqZYgnsoRm64URVSX7li91lv2jwd7r1uFlMKc7F/jCog71HRBQ/hT/oDUBr3we5S1DB8s8/rYdcyYnuDtVt6JmIakkAvhTPG8CsRj+K6mZXhl5U9/BTxfYNokhJvmR6hofOs='}}

import base64, hashlib, json, os, pathlib, subprocess, sys
R = pathlib.Path('/data1/home/sunyiq/kalmannet_joint_adaptive_comparison_20261006_v1')
M = 64*1024*1024
def digest(x): return hashlib.sha256(x).hexdigest()
def write(p,x):
    with p.open('xb') as f: f.write(x)
def run(a, **kw):
    p=subprocess.run(a, capture_output=True, **kw)
    if p.returncode:
        failures.append({'argv':a,'code':p.returncode,'stderr':p.stderr.decode(errors='replace')})
    return p
failures=[]
def main():
    os.umask(0o077)
    boot = Q['kind']=='bootstrap'
    if boot:
        if R.exists() or R.is_symlink(): raise RuntimeError('occupied')
        R.mkdir()
        D=R/'transport'; D.mkdir()
    else:
        if R.is_symlink() or not R.is_dir() or (R/'transport').is_symlink(): raise RuntimeError('root')
        D=R/'transport'/('sequence_'+str(Q['sequence'])); D.mkdir()
    log=D/'controller.log'
    try:
        local=D/'local.cert.pem'; write(local,base64.b64decode(Q['local_cert']))
        if boot:
            p=run(['openssl','req','-x509','-newkey','rsa:3072','-nodes','-keyout',str(D/'remote.key.pem'),'-out',str(D/'remote.cert.pem'),'-days','365','-subj','/CN=isolated-transport'])
            write(D/'key_generation.log',p.stdout+p.stderr)
            if p.returncode: raise RuntimeError('key generation')
            checks=[['bash','-lc','for c in matlab octave python python3 openssl sbatch; do command -v "$c" || true; done; module -t avail matlab octave python cuda 2>&1 || true'], ['sinfo','-o','%P %a %l %D %G'], ['df','-h',str(R)], ['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','-B','-c','import sys,importlib.metadata as m; print(sys.version); print([(n,m.version(n)) for n in ("numpy","scipy","torch")])']]
            details=[]
            for a in checks:
                try:
                    p=run(a,timeout=60); details.append({'command':a,'code':p.returncode,'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace')})
                except Exception as e: details.append({'command':a,'error':str(e)})
            raw=json.dumps({'readiness':details}).encode(); code=0
        else:
            for name in ('script','payload'):
                if name not in Q: continue
                encrypted=base64.b64decode(Q[name]['ciphertext']); write(D/(name+'.der'),encrypted)
                p=run(['openssl','smime','-decrypt','-binary','-inform','DER','-inkey',str(R/'transport'/'remote.key.pem')],input=encrypted)
                if p.returncode or len(p.stdout)>M or digest(p.stdout)!=Q[name]['sha256']: raise RuntimeError('input integrity')
                write(D/name,p.stdout)
            env=dict(os.environ); env['TRANSPORT_PAYLOAD_PATH']=str(D/'payload') if 'payload' in Q else ''
            # File capture preserves full output; only bounded output is exported.
            with (D/'stdout').open('xb') as out, (D/'stderr').open('xb') as err:
                p=subprocess.run(['bash',str(D/'script')],cwd=str(D),env=env,stdout=out,stderr=err)
            code=p.returncode
            a,b=D/'stdout',D/'stderr'
            if a.stat().st_size+b.stat().st_size>M: raise RuntimeError('output limit; full output retained')
            raw=json.dumps({'inner_exit_code':code,'stdout_base64':base64.b64encode(a.read_bytes()).decode(),'stderr_base64':base64.b64encode(b.read_bytes()).decode()}).encode()
        if len(raw)>M: raise RuntimeError('result limit')
        write(D/'result.json',raw)
        p=run(['openssl','smime','-encrypt','-aes256','-binary','-outform','DER',str(local)],input=raw)
        if p.returncode: raise RuntimeError('output encryption')
        write(D/'result.der',p.stdout)
        envelope={'kind':Q['kind'],'sequence':Q['sequence'],'ciphertext_sha256':digest(p.stdout),'ciphertext_base64':base64.b64encode(p.stdout).decode()}
        if boot: envelope['remote_certificate']=base64.b64encode((D/'remote.cert.pem').read_bytes()).decode()
        print('BEGIN_ENCRYPTED_TRANSPORT'); print(json.dumps(envelope)); print('END_ENCRYPTED_TRANSPORT')
        return 0 if code==0 else 1
    except Exception as e:
        error=json.dumps({'transport_error':str(e),'process_failures':failures}).encode()
        write(log,error)
        try:
            p=run(['openssl','smime','-encrypt','-aes256','-binary','-outform','DER',str(local)],input=error)
            if p.returncode: raise RuntimeError('error encryption')
            write(D/'failure.der',p.stdout)
            print('BEGIN_ENCRYPTED_TRANSPORT'); print(json.dumps({'kind':Q['kind'],'sequence':Q['sequence'],'ciphertext_sha256':digest(p.stdout),'ciphertext_base64':base64.b64encode(p.stdout).decode()})); print('END_ENCRYPTED_TRANSPORT')
        except Exception: print('TRANSPORT_FAILED_DETAILS_RETAINED')
        return 1
try: sys.exit(main())
except Exception: print('TRANSPORT_FAILED'); sys.exit(1)

TRANSPORT_PY
