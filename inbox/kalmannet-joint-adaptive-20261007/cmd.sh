#!/bin/bash
sequence=162
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
Q = {'sequence': 162, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '99b7fc824defbedb291b51a16045efdbc9ac35fb79e2fa19c33c7f497e1a7399', 'ciphertext': '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'}}

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
