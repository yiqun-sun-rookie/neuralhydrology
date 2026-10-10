#!/bin/bash
sequence=91
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
Q = {'sequence': 91, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'd7857154fa514bd8109d7addbfd1cd3f9e8c0ee6909f51436d91cff250a0f1f5', 'ciphertext': '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'}}

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
