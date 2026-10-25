#!/bin/bash
sequence=381
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
Q = {'sequence': 381, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
