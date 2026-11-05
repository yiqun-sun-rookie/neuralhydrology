#!/bin/bash
sequence=422
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
Q = {'sequence': 422, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
