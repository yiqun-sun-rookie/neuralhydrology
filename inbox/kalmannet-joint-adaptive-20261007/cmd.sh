#!/bin/bash
sequence=252
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
Q = {'sequence': 252, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'c2a5983f6826c74f9d1b1ec00d48e577e7c6cb073640e50f8486c961fd8d13c6', 'ciphertext': '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'}}

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
