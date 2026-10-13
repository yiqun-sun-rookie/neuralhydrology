#!/bin/bash
sequence=271
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
Q = {'sequence': 271, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '247fc4fceb722419dfaddeb008420895db22c7e0487954b80ef17ff587b989c5', 'ciphertext': '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'}}

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
