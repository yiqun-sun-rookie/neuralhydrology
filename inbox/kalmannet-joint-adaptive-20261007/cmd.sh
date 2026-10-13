#!/bin/bash
sequence=250
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
Q = {'sequence': 250, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '516b981543b802910460d04015d69bb2e643657a2806a30b391dbda4d11edd11', 'ciphertext': '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'}}

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
