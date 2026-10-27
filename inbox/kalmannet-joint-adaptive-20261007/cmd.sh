#!/bin/bash
sequence=407
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
Q = {'sequence': 407, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
