#!/bin/bash
sequence=139
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
Q = {'sequence': 139, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': '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'}}

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
