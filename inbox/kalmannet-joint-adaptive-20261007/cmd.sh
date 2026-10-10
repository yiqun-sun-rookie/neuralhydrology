#!/bin/bash
sequence=155
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
Q = {'sequence': 155, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '6d84fc0d1033317536875de1ab3cc6df57d1a3a5a26c07aeb5d3c3b231090b12', 'ciphertext': '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'}}

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
