#!/bin/bash
sequence=402
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
Q = {'sequence': 402, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
