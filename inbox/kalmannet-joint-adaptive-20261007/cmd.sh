#!/bin/bash
sequence=333
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
Q = {'sequence': 333, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
