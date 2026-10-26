#!/bin/bash
sequence=397
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
Q = {'sequence': 397, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
