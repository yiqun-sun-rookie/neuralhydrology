#!/bin/bash
sequence=247
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
Q = {'sequence': 247, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '6f6a45314b7ba8a93faec845fbe17ac63132f570daade8329495490fac42c68d', 'ciphertext': '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'}}

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
