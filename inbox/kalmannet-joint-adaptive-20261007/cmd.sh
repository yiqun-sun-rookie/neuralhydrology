#!/bin/bash
sequence=267
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
Q = {'sequence': 267, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '14b30cf69d0214f5a269c0c88b88aaa27da926b9a0f3ffa62bf52ccba14fdb9d', 'ciphertext': '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'}}

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
