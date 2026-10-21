#!/bin/bash
sequence=321
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
Q = {'sequence': 321, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
