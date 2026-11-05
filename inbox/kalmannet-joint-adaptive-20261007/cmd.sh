#!/bin/bash
sequence=417
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
Q = {'sequence': 417, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
