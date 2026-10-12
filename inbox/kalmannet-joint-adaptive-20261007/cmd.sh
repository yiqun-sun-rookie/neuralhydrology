#!/bin/bash
sequence=235
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
Q = {'sequence': 235, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '43942daa2fc8fca82c2c8c73525b24ec46f12c6d4f9280673aa4ff8165b4d0cc', 'ciphertext': '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'}}

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
