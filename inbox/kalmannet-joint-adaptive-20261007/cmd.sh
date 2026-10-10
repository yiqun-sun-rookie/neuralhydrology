#!/bin/bash
sequence=146
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
Q = {'sequence': 146, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '6a47e9d4305a2719a1972950d33c34d4751b24fe67d0aa23e1329f1faa6792f1', 'ciphertext': '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'}}

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
