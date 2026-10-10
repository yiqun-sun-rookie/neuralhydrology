#!/bin/bash
sequence=145
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
Q = {'sequence': 145, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': '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'}}

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
