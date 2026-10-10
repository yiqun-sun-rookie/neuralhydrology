#!/bin/bash
sequence=152
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
Q = {'sequence': 152, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '5f6379f1f6ebc2b1595d33ed248f6c89e46e49d929bfd105150f212e2552505a', 'ciphertext': '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'}}

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
