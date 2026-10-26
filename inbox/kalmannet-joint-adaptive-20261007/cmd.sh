#!/bin/bash
sequence=395
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
Q = {'sequence': 395, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
