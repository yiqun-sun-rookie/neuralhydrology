#!/bin/bash
sequence=280
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
Q = {'sequence': 280, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '98b1e06a1c17470eceec2daad84349f5f7b0e09cd3afda5b2c1d65811d992af2', 'ciphertext': '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'}}

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
