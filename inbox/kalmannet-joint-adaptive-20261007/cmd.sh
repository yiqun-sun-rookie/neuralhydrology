#!/bin/bash
sequence=380
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
Q = {'sequence': 380, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
