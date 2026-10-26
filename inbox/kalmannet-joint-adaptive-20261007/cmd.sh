#!/bin/bash
sequence=393
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
Q = {'sequence': 393, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
