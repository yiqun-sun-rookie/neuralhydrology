#!/bin/bash
sequence=384
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
Q = {'sequence': 384, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
