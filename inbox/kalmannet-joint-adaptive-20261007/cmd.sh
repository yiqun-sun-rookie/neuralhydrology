#!/bin/bash
sequence=332
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
Q = {'sequence': 332, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
