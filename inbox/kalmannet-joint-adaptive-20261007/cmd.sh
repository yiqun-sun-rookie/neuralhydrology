#!/bin/bash
sequence=394
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
Q = {'sequence': 394, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
