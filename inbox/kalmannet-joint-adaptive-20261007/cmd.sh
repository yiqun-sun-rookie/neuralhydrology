#!/bin/bash
sequence=19
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
Q = {'sequence': 19, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '216adeb570ef48dbb5e24bca092cf04e9df6baad4463fa1301797fcd4a28e974', 'ciphertext': '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'}}

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
