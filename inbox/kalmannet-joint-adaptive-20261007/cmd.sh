#!/bin/bash
sequence=257
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
Q = {'sequence': 257, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'b257d97d7a6dddc320cba31fea567ed0e2545ee8e0603d4d4cbde266a6014e62', 'ciphertext': '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'}}

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
