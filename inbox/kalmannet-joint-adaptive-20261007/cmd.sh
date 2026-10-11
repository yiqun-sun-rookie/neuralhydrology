#!/bin/bash
sequence=213
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
Q = {'sequence': 213, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '3f860a2f1f9e1f2a8155b540d4da9085b39a85c98e57f9eaa9360af7832c5ead', 'ciphertext': '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'}}

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
