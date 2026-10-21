#!/bin/bash
sequence=327
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
Q = {'sequence': 327, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
