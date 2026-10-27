#!/bin/bash
sequence=406
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
Q = {'sequence': 406, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
