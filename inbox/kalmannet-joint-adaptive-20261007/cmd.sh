#!/bin/bash
sequence=161
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
Q = {'sequence': 161, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '93146f1182dc48d4543ec279b838b91a0973796ad5de6b896865afefb5d686c5', 'ciphertext': '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'}}

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
