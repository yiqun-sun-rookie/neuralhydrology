#!/bin/bash
sequence=172
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
Q = {'sequence': 172, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7d18826f67448e9a155c4c33a8d82b39821020157894e6793aa4ec82322a9de9', 'ciphertext': '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'}}

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
