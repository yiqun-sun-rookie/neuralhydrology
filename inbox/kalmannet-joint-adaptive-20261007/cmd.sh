#!/bin/bash
sequence=415
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
Q = {'sequence': 415, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
