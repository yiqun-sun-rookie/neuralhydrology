#!/bin/bash
sequence=386
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
Q = {'sequence': 386, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
