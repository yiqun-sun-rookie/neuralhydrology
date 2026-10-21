#!/bin/bash
sequence=324
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
Q = {'sequence': 324, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
