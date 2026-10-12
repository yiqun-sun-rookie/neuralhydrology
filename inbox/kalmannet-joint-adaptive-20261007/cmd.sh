#!/bin/bash
sequence=240
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
Q = {'sequence': 240, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7ede2b69c1530c530bdecbaf887d9dd74087b55ed71e5dd2dabe1983f3c09217', 'ciphertext': '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'}}

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
