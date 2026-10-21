#!/bin/bash
sequence=336
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
Q = {'sequence': 336, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
