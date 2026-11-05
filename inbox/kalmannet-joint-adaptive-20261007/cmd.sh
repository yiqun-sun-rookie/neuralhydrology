#!/bin/bash
sequence=420
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
Q = {'sequence': 420, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
