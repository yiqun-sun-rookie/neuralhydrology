#!/bin/bash
sequence=401
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
Q = {'sequence': 401, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
