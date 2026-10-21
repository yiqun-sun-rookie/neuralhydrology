#!/bin/bash
sequence=309
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
Q = {'sequence': 309, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0265fc1769d5d289a6b644de5d33affff19d880927de3cafbfb5fb0ca3648499', 'ciphertext': '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'}}

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
