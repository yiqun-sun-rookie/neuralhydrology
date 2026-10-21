#!/bin/bash
sequence=343
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
Q = {'sequence': 343, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
