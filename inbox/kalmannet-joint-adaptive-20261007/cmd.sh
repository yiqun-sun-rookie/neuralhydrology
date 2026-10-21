#!/bin/bash
sequence=330
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
Q = {'sequence': 330, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
