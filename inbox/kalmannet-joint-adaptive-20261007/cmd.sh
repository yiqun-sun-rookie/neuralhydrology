#!/bin/bash
sequence=20
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
Q = {'sequence': 20, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1ab4546a85baeee152e8c393b1d8c77120bc8d9ddb3880ffaa2c3c60269bd839', 'ciphertext': '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'}}

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
