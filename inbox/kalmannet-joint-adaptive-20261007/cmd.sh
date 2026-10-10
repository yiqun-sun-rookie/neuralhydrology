#!/bin/bash
sequence=113
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
Q = {'sequence': 113, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '31c6feb6783977a0ddb1d485ec6482be5a1d83b348dd24917ce70dbf759e5b78', 'ciphertext': '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'}}

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
