#!/bin/bash
sequence=151
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
Q = {'sequence': 151, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': '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'}}

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
