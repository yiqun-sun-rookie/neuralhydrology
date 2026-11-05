#!/bin/bash
sequence=425
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
Q = {'sequence': 425, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
