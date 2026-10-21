#!/bin/bash
sequence=335
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
Q = {'sequence': 335, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
