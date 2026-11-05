#!/bin/bash
sequence=416
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
Q = {'sequence': 416, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
