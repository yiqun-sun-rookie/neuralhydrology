#!/bin/bash
sequence=426
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
Q = {'sequence': 426, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
