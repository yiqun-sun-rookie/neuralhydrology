#!/bin/bash
sequence=24
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
Q = {'sequence': 24, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7a5d2f28470aa04eecf027990b9b7b7d20bfc563b38f0bd59df1c82fa4a9442b', 'ciphertext': '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'}}

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
