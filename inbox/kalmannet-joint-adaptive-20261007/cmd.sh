#!/bin/bash
sequence=389
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
Q = {'sequence': 389, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
