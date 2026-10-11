#!/bin/bash
sequence=166
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
Q = {'sequence': 166, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0ba0cefa30faa05619a1c47712ca8f4076b3618d8e06267a9bcf70574346b3a5', 'ciphertext': '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'}}

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
