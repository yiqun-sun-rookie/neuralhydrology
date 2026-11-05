#!/bin/bash
sequence=419
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
Q = {'sequence': 419, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
