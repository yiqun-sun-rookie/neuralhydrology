#!/bin/bash
sequence=341
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
Q = {'sequence': 341, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
