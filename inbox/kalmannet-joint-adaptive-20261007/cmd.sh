#!/bin/bash
sequence=424
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
Q = {'sequence': 424, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
