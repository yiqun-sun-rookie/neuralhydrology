#!/bin/bash
sequence=342
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
Q = {'sequence': 342, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
