#!/bin/bash
sequence=427
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
Q = {'sequence': 427, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1e51240b287d7784c3e0ea9b3c4e0f63588579c7629dbadcf89580fe3f473df6', 'ciphertext': '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'}}

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
