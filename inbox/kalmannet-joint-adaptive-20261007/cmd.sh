#!/bin/bash
sequence=183
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
Q = {'sequence': 183, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '34c6968dd176a5ad38bd8b90efe1ec356d90c731e5e2bc5b8f8cad1f5e2879aa', 'ciphertext': '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'}}

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
