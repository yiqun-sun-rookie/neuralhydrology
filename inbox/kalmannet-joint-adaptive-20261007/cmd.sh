#!/bin/bash
sequence=134
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
Q = {'sequence': 134, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': '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'}}

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
