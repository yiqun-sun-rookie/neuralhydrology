#!/bin/bash
sequence=328
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
Q = {'sequence': 328, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
