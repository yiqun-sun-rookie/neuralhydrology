#!/bin/bash
sequence=17
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
Q = {'sequence': 17, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '216adeb570ef48dbb5e24bca092cf04e9df6baad4463fa1301797fcd4a28e974', 'ciphertext': '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'}}

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
