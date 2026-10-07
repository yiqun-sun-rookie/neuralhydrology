#!/bin/bash
sequence=4
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
Q = {'sequence': 4, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '524b7740ec8e8ba11d8f007e047f304f6bdf4d02093b6dedb03e5efffeba0c06', 'ciphertext': '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'}}

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
