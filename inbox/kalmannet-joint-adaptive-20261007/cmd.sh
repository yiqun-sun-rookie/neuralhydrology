#!/bin/bash
sequence=325
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
Q = {'sequence': 325, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
