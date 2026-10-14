#!/bin/bash
sequence=289
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
Q = {'sequence': 289, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '552a3f806c22465f8bdefb7407a8f17c8203d09089b437833be8dd297f0f92dd', 'ciphertext': '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'}}

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
