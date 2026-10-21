#!/bin/bash
sequence=315
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
Q = {'sequence': 315, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'b9b8fedadd1fa81263de0e5ddc9ba3cfc017b8bb425915404c0d3b363b971528', 'ciphertext': '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'}}

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
