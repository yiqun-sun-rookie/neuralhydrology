#!/bin/bash
sequence=294
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
Q = {'sequence': 294, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ff25df613067cd7c13772dfdd9f0779e89ae398f0f65ffe20b47e78428394b93', 'ciphertext': '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'}}

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
