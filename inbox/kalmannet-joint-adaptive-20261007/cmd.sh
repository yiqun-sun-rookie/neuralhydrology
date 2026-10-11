#!/bin/bash
sequence=194
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
Q = {'sequence': 194, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '17d1e6796ef738b79c490af05c6f326d6dc8e800c09414cfa352f4e26b511e41', 'ciphertext': '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'}}

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
