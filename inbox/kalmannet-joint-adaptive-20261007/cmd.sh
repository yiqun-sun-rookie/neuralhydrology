#!/bin/bash
sequence=423
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
Q = {'sequence': 423, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
