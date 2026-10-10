#!/bin/bash
sequence=123
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
Q = {'sequence': 123, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'b5419de3447208c8a001c579dd8811213891407e39dc15334ffe6b0ea8c2e022', 'ciphertext': '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'}}

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
