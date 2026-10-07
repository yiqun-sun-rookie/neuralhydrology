#!/bin/bash
sequence=35
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
Q = {'sequence': 35, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '319474d8ca5cceb662285c3499651f413a9d171c83535e35d7cafd46617491d0', 'ciphertext': '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'}}

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
