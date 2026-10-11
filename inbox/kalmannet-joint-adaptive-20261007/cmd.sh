#!/bin/bash
sequence=214
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
Q = {'sequence': 214, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7927f022f34460686512cd0b221d045ff117178d8962eb24a75f3ea48baa6e03', 'ciphertext': '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'}}

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
