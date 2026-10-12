#!/bin/bash
sequence=241
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
Q = {'sequence': 241, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1a08a081b2aad3770c1e07135db0727425efe56c38972ac247febc9954a74a21', 'ciphertext': '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'}}

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
