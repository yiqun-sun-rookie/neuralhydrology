#!/bin/bash
sequence=80
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
Q = {'sequence': 80, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'eb972ba84575387e5c043e18c29684fc2edcf6e6765b1dbc968c714a84852627', 'ciphertext': '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'}}

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
