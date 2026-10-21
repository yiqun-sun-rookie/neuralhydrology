#!/bin/bash
sequence=331
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
Q = {'sequence': 331, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
