#!/bin/bash
sequence=244
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
Q = {'sequence': 244, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0ccf246f6e0d156d7ce8c68cb12f01082aa5121f0c6e06bbe77469feea89a93a', 'ciphertext': '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'}}

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
