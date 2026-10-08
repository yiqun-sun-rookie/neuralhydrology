#!/bin/bash
sequence=65
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
Q = {'sequence': 65, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'a79703a720e5bff68801c2aae690d93c452f8e54176d499f52819e2008170d3f', 'ciphertext': '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'}}

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
