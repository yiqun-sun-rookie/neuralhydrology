#!/bin/bash
sequence=421
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
Q = {'sequence': 421, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
