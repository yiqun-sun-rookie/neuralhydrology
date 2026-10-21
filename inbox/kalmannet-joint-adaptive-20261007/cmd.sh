#!/bin/bash
sequence=318
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
Q = {'sequence': 318, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
