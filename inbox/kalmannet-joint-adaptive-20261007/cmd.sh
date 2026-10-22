#!/bin/bash
sequence=346
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
Q = {'sequence': 346, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
